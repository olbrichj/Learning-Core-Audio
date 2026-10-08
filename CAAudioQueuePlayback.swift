import Playgrounds

import AudioToolbox

let kPlaybackFileLocation = "<fully qualified file path>"
let kNumberPlaybackBuffers = 3

//MARK: user data struct
final class MyPlayer {
	var playbackFile: AudioFileID?
	var packetPosition: Int64 = 0
	var numPacketsToRead: UInt32 = 0
	var packetDescs: [AudioStreamPacketDescription] = []
	var isDone: Bool = true
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

func calculateBytesForTime(file: AudioFileID?, inDesc: AudioStreamBasicDescription, time: Float64) -> (UInt32, UInt32) {
	var outBufferSize: UInt32 = 0
	var maxPacketSize: UInt32 = 0
	var propSize = UInt32(MemoryLayout<UInt32>.size)
	check(error: AudioFileGetProperty(
			file!,
			kAudioFilePropertyPacketSizeUpperBound,
			&propSize,
			&maxPacketSize
		),
		description: "Couldn't get file's max packet size"
	)
	
	let maxBufferSize: UInt32 = 0x10000
	let minBufferSize: UInt32 = 0x4000
	
	if inDesc.mFramesPerPacket > 0 {
		let numPacketsForTime: Float64 = inDesc.mSampleRate / Float64(inDesc.mFramesPerPacket) * time
		outBufferSize = UInt32(numPacketsForTime) * maxPacketSize
	} else {
		outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize
	}
	
	if outBufferSize > maxBufferSize, outBufferSize > maxPacketSize {
		outBufferSize = maxBufferSize
	} else if outBufferSize < minBufferSize {
		outBufferSize = minBufferSize
	}
	return (outBufferSize, outBufferSize / maxPacketSize)
}

func copyEncoderCookieToQueue(file: AudioFileID, queue: AudioQueueRef) {
	var propertySize: UInt32 = 0
	let result = AudioFileGetPropertyInfo(
		file,
		kAudioFilePropertyMagicCookieData,
		&propertySize,
		nil
	)
	
	guard result == noErr, propertySize > 0 else { return }
	
	var magicCookie = Data(count: Int(propertySize))
	magicCookie.withUnsafeMutableBytes { buffer in
		check(error: AudioFileGetProperty(
				file,
				kAudioFilePropertyMagicCookieData,
				&propertySize,
				buffer.baseAddress!
			),
			description: "get cookie from file failed"
		)
	}
	
	magicCookie.withUnsafeBytes { buffer in
		check(error: AudioQueueSetProperty(
				queue,
				kAudioQueueProperty_MagicCookie,
				buffer.baseAddress!,
				propertySize
			),
			description: "Set cookie on queue failed"
		)
	}
}

//MARK: playback callback
let MyAQOutputCallback: AudioQueueOutputCallback = { inUserData, inAQ, inCompleteAQBuffer in
	guard let inUserData else { return }
	let aqp = Unmanaged<MyPlayer>.fromOpaque(inUserData).takeUnretainedValue()
	
	guard !aqp.isDone else { return }
	
	var numBytes: UInt32 = 0
	var nPackets = aqp.numPacketsToRead
	
	if aqp.packetDescs.isEmpty {
		check(error: AudioFileReadPackets(
				aqp.playbackFile!,
				false,
				&numBytes,
				nil,
				aqp.packetPosition,
				&nPackets,
				inCompleteAQBuffer.pointee.mAudioData
			),
			description: "AudioFIleReadPackets Failed"
		)
		
		if nPackets > 0 {
			inCompleteAQBuffer.pointee.mAudioDataByteSize = numBytes
			AudioQueueEnqueueBuffer(inAQ, inCompleteAQBuffer, 0, nil)
		} else {
			check(error:AudioQueueStop(inAQ, false), description: "AudioQueueStop failed")
			aqp.isDone = true
		}
	} else {
		aqp.packetDescs.withUnsafeMutableBufferPointer { descriptions in
			check(error: AudioFileReadPackets(
					aqp.playbackFile!,
					false,
					&numBytes,
					descriptions.baseAddress,
					aqp.packetPosition,
					&nPackets,
					inCompleteAQBuffer.pointee.mAudioData
				),
				description: "AudioFIleReadPackets Failed"
			)
			
			if nPackets > 0 {
				inCompleteAQBuffer.pointee.mAudioDataByteSize = numBytes
				AudioQueueEnqueueBuffer(
					inAQ,
					inCompleteAQBuffer,
					nPackets,
					descriptions.baseAddress
				)
			} else {
				check(error:AudioQueueStop(inAQ, false), description: "AudioQueueStop failed")
				aqp.isDone = true
			}
		}
	}
	aqp.packetPosition += Int64(nPackets)
}

//MARK: main
func playback() {
	// Open an audio file
	let player = MyPlayer()
	let playerPointer = Unmanaged.passUnretained(player).toOpaque()
	
	let myFileURL = NSURL(fileURLWithPath: kPlaybackFileLocation)
	guard FileManager.default.fileExists(atPath: myFileURL.path!) else {
		fatalError("File does not exist: \(myFileURL.path)")
	}
	
	check(error: AudioFileOpenURL(
			myFileURL,
			.readPermission,
			0,
			&player.playbackFile
		),
		description: "AudioFileOpenURL failed"
	)
	
	// setup format
	var dataFormat = AudioStreamBasicDescription()
	var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
	check(error: AudioFileGetProperty(
			player.playbackFile!,
			kAudioFilePropertyDataFormat,
			&propSize, &dataFormat
		),
		description: "Coudn't get file's data format"
	)
	
	// setup queue
	var queue: AudioQueueRef!
	check(error: AudioQueueNewOutput(
			&dataFormat,
			MyAQOutputCallback,
			playerPointer,
			nil,
			nil,
			0,
			&queue
		),
		description: "AudioQueueNewOutput failed"
	)
	
	let (bufferByteSize, packetCount) = calculateBytesForTime(
		file: player.playbackFile,
		inDesc: dataFormat,
		time: 0.5
	)
	player.numPacketsToRead = packetCount
	
	var isFormatVBR = dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0
	if isFormatVBR {
		player.packetDescs = Array(repeating: AudioStreamPacketDescription(), count: Int(player.numPacketsToRead))
	} else {
		player.packetDescs = []
	}
	
	copyEncoderCookieToQueue(file: player.playbackFile!, queue: queue)
	
	var buffers = [AudioQueueBufferRef?](repeating: nil, count: kNumberPlaybackBuffers)
	player.isDone = false
	player.packetPosition = 0
	for i in 0..<kNumberPlaybackBuffers {
		check(error:AudioQueueAllocateBuffer(
				queue,
				bufferByteSize,
				&buffers[i]
			),
			description: "AudioQueueAllocateBuffer failed"
		)
		
		MyAQOutputCallback(playerPointer, queue, buffers[i]!)
		
		if player.isDone { break }
	}
	
	// start queue
	check(error: AudioQueueStart(queue, nil), description: "AudioQueueStart failed")
	
	print("playing")
	repeat {
		CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, false)
	} while !player.isDone
	
	// cleanup queue when finished
	player.isDone = true
	check(error: AudioQueueStop(queue, true), description: "AudioQueueStop failed")
	AudioFileClose(player.playbackFile!)
}


#Playground {
	print("Learning Core Audio - Chapter 5")
	//playback()
}
