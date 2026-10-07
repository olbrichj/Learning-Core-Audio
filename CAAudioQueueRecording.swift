import Playgrounds

import AudioToolbox
import CoreAudioTypes

let kNumberRecordBuffers = 3

//MARK: user data struc
class MyRecorder {
	var recordFile: AudioFileID?
	var recordPacket: Int64 = 0
	var running: Bool = false
}

//MARK: utility functions
func check(error: OSStatus, description: String) {
	guard error != noErr else { return }
	
	let errorString = error.bigEndian
	let formatString: String? = withUnsafeBytes(of: errorString) { buffer in
		let bytes = Array(buffer.bindMemory(to: UInt8.self))
		return String(bytes: bytes, encoding: .utf8)
	}
	
	if let formatString {
		print("Error: \(description) (\(formatString))")
	} else {
		print("Error: \(description) (\(error))")
	}
	exit(1)
}

func defaultInputDeviceSampleRate() -> Float64 {
	var error = noErr
	var deviceId: AudioDeviceID = 0
	
	var propertyAddress = AudioObjectPropertyAddress()
	var propertySize: UInt32 = 0
	propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
	propertyAddress.mElement = 0
	propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
	error = AudioObjectGetPropertyData(
		AudioObjectID(kAudioObjectSystemObject),
		&propertyAddress,
		0,
		nil,
		&propertySize,
		&deviceId
	)
	if error != noErr {
		print("can't determine default InputDevice deviceId - exiting")
		exit(1)
	}
	
	propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
	propertyAddress.mElement = 0
	propertySize = UInt32(MemoryLayout<Float64>.size)
	var outSampleRate: Float64! = 0
	error = AudioObjectGetPropertyData(
		deviceId,
		&propertyAddress,
		0,
		nil,
		&propertySize,
		&outSampleRate
	)
	if error != noErr {
		print("can't determine default InputDevice sampleRate - exiting")
		exit(1)
	}
	
	return outSampleRate
}

func computeRecordBufferSize(format: AudioStreamBasicDescription, queue: AudioQueueRef, seconds: Float64) -> UInt32 {
	var packets: UInt32 = 0
	var frames: UInt32 = 0
	var bytes: UInt32 = 0
	
	frames = UInt32(ceil(seconds * format.mSampleRate))
	if format.mBytesPerFrame > 0 {
		bytes = frames * format.mBytesPerFrame
	} else {
		var maxPacketSize: UInt32 = 0
		if format.mBytesPerPacket > 0 {
			maxPacketSize = format.mBytesPerPacket
		} else {
			var propertySize = UInt32(MemoryLayout<UInt32>.size)
			check(error: AudioQueueGetProperty(
					queue,
					kAudioConverterPropertyMaximumOutputPacketSize,
					&maxPacketSize,
					&propertySize
				),
				description: "Couldn't get queue's maximum output packet size"
			)
		}
		
		if format.mFramesPerPacket > 0 {
			packets = frames / format.mFramesPerPacket
		} else {
			packets = frames
		}
		
		if packets == 0 {
			packets = 1
		}
		bytes = packets * maxPacketSize
	}
	
	return bytes
}

func copyEncoderCookieToFile(queue: AudioQueueRef, file: AudioFileID?) {
	guard let file else { return }
	var error = noErr
	var propertySize: UInt32 = 0
	
	error = AudioQueueGetPropertySize(
		queue,
		kAudioQueueProperty_MagicCookie,
		&propertySize
	)
	guard error == noErr, propertySize > 0 else {
		print("no magic cookie")
		return
	}
	
	var magicCookie = Data(count: Int(propertySize))
	magicCookie.withUnsafeMutableBytes { buffer in
		check(error: AudioQueueGetProperty(
				queue,
				kAudioQueueProperty_MagicCookie,
				buffer.baseAddress!,
				&propertySize
			),
			description: "Couldn't get audio queue's magic cookie"
		)
	}
	
	magicCookie.withUnsafeBytes { buffer in
		check(error: AudioFileSetProperty(
				file,
				kAudioFilePropertyMagicCookieData,
				propertySize,
				buffer.baseAddress!
			),
			description: "Couldn't set audio file's magic cookie"
		)
	}
}

//MARK: record callback function
let MyAQInputCallback: AudioQueueInputCallback = { inUserData, inQueue, inBuffer, inStartTime, inNumPackets, inPacketDesc in
	guard let inUserData else { return }
	let recorder = Unmanaged<MyRecorder>.fromOpaque(inUserData).takeUnretainedValue()
	
	guard inNumPackets > 0 else { return }
	
	var ioNumPackets = inNumPackets
	
	check(error: AudioFileWritePackets(
			recorder.recordFile!,
			false,
			inBuffer.pointee.mAudioDataByteSize,
			inPacketDesc,
			recorder.recordPacket,
			&ioNumPackets,
			inBuffer.pointee.mAudioData
		),
		description: "AudioFileWritePackets failed"
	)
	
	recorder.recordPacket += Int64(ioNumPackets)
	
	if recorder.running {
		check(error: AudioQueueEnqueueBuffer(
				inQueue,
				inBuffer,
				0,
				nil),
			description: "AudioQueueEnqueueBuffer failed"
		)
	}
}

//MARK: main function
func record() {
	// setup format
	var recorder = MyRecorder()
	let recorderPointer = Unmanaged.passUnretained(recorder).toOpaque()
	var recordFormat = AudioStreamBasicDescription()
	recordFormat.mFormatID = kAudioFormatMPEG4AAC
	recordFormat.mChannelsPerFrame = 2
	recordFormat.mSampleRate = defaultInputDeviceSampleRate()
	
	var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
	check(error: AudioFormatGetProperty(
			kAudioFormatProperty_FormatInfo,
			0,
			nil,
			&propSize,
			&recordFormat
		),
		description: "AudioFormatGetProperty failed"
	)
	
	// setup queue
	var queue: AudioQueueRef!
	check(error: AudioQueueNewInput(
			&recordFormat,
			MyAQInputCallback,
			recorderPointer,
			nil,
			nil,
			0,
			&queue
		),
		description: "AudioQueueNewInput failed"
	)
	
	var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
	check(error: AudioQueueGetProperty(
			queue,
			kAudioConverterCurrentOutputStreamDescription,
			&recordFormat,
			&size
		),
		description: "Couldn't get queue's format"
	)
	
	// setup file
	let currentPath = FileManager.default.currentDirectoryPath
	//let currentPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
	let fileURL = URL(fileURLWithPath: currentPath).appendingPathComponent("output.caf")
	check(error: AudioFileCreateWithURL(
			fileURL as NSURL,
			kAudioFileCAFType,
			&recordFormat,
			.eraseFile,
			&recorder.recordFile
		),
		description: "AudioFileCreateWithURL failed"
	)
	
	copyEncoderCookieToFile(queue:queue, file:recorder.recordFile)
	
	// other setup as needed
	let bufferByteSize = computeRecordBufferSize(format:recordFormat, queue:queue, seconds: 0.5)
	for bufferIndex in 0..<kNumberRecordBuffers {
		var buffer: AudioQueueBufferRef!
		check(error: AudioQueueAllocateBuffer(
				queue,
				bufferByteSize,
				&buffer
			),
			description: "AudioQueueAllocateBuffer failed"
		)
		check(error: AudioQueueEnqueueBuffer(
				queue,
				buffer,
				0,
				nil
			),
			description: "AudioQueueEnqueueBuffer failed"
		)
	}
	
	// start queue
	recorder.running = true
	check(error: AudioQueueStart(
			queue,
			nil
		),
		description: "AudioQueueStart failed"
	)
	
	print("recording for 5 seconds...")
	RunLoop.current.run(until: Date(timeIntervalSinceNow: 5.0))
	
	// stop queue
	print("recording done")
	recorder.running = false
	check(error: AudioQueueStop(
			queue,
			true
		),
		description: "AudioQueueStop Failed"
	)
	
	copyEncoderCookieToFile(queue:queue, file:recorder.recordFile)
	
	AudioQueueDispose(queue, true)
	AudioFileClose(recorder.recordFile!)
}

#Playground {
	print("Learning Core Audio - Chapter 4")
	//record()
}
