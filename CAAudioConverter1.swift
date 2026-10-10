import Playgrounds

import AudioToolbox
import CoreAudioTypes

let kInputFileLocation = "<fully qualified file path>"
let kOutputFileLocation = "<fully qualified file path>.aif"

//MARK: user data
final class MyAudioConverterSettings {
	var inputFormat = AudioStreamBasicDescription()
	var outputFormat = AudioStreamBasicDescription()
	
	var inputFile: AudioFileID?
	var outputFile: AudioFileID?
	
	var inputFilePacketIndex: UInt64 = 0
	var inputFilePacketCount: UInt64 = 0
	var inputFilePacketMaxSize: UInt64 = 0
	var inputFilePacketDescriptions: [AudioStreamPacketDescription] = []
	
	var sourceBuffer: UnsafeMutableRawPointer?
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


func convert(settings: MyAudioConverterSettings) {
	var settings = settings
	var audioConverter: AudioConverterRef!
	check(error: AudioConverterNew(
			&settings.inputFormat,
			&settings.outputFormat,
			&audioConverter
		),
		description: "AudioConverterNew failed"
	)

	var packetsPerBuffer: UInt32 = 0
	var outputBufferSize: UInt32 = 32 * 1024
	var sizePerPacket: UInt32 = settings.inputFormat.mBytesPerPacket

	if sizePerPacket == 0 {
		var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)
		check(error: AudioConverterGetProperty(
				audioConverter,
				kAudioConverterPropertyMaximumOutputPacketSize,
				&size,
				&sizePerPacket
			),
			description: "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize"
		)

		if sizePerPacket > outputBufferSize {
			outputBufferSize = sizePerPacket
		}

		packetsPerBuffer = outputBufferSize / sizePerPacket
		settings.inputFilePacketDescriptions = Array(
			repeating: AudioStreamPacketDescription(),
			count: Int(packetsPerBuffer)
		)
	} else {
		packetsPerBuffer = outputBufferSize / sizePerPacket
	}

	var outputBuffer = UnsafeMutablePointer<UInt8>.allocate(
		capacity: Int(outputBufferSize)
	)
	outputBuffer.initialize(repeating: 0, count: Int(outputBufferSize))
	defer { outputBuffer.deallocate() }

	var outputFilePacketPosition: UInt32 = 0

	while true {
		var convertedData = AudioBufferList.allocate(maximumBuffers: 1)
		convertedData[0] = AudioBuffer(
			mNumberChannels: settings.outputFormat.mChannelsPerFrame,
			mDataByteSize: outputBufferSize,
			mData: outputBuffer
		)

		var ioOutputDataPackets = packetsPerBuffer

		let packetDescPtr: UnsafeMutablePointer<AudioStreamPacketDescription>? =
			settings.inputFilePacketDescriptions.isEmpty
				? nil
				: settings.inputFilePacketDescriptions.withUnsafeMutableBufferPointer {
					$0.baseAddress
				}

		let error = AudioConverterFillComplexBuffer(
			audioConverter,
			MyAudioConverterCallback,
			Unmanaged.passUnretained(settings).toOpaque(),
			&ioOutputDataPackets,
			convertedData.unsafeMutablePointer,
			packetDescPtr
		)

		guard error == noErr, ioOutputDataPackets > 0 else {
			break
		}

		let outputByteCount = ioOutputDataPackets * settings.outputFormat.mBytesPerPacket

		var packetsToWrite = ioOutputDataPackets

		check(error: AudioFileWritePackets(
				settings.outputFile!,
				false,
				outputByteCount,
				nil,
				Int64(outputFilePacketPosition /
					  settings.outputFormat.mBytesPerPacket),
				&packetsToWrite,
				convertedData[0].mData!
			),
			description: "Couldn't write packets to file"
		)

		outputFilePacketPosition +=
			packetsToWrite * settings.outputFormat.mBytesPerPacket
	}

	AudioConverterDispose(audioConverter)
}

//MARK: converter callback function
let MyAudioConverterCallback: AudioConverterComplexInputDataProc = { inAudioConverter, ioDataPacketCount, ioData, outDataPacketDescription, inUserData in
	guard let inUserData else { return noErr }
	let audioConverterSettings = Unmanaged<MyAudioConverterSettings>.fromOpaque(inUserData).takeUnretainedValue()

	let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
	bufferList[0].mData = nil
	bufferList[0].mDataByteSize = 0
	
	var ioDataPacketCount = ioDataPacketCount
	let remaining = audioConverterSettings.inputFilePacketCount
		- audioConverterSettings.inputFilePacketIndex

	ioDataPacketCount.pointee = UInt32(
		min(UInt64(ioDataPacketCount.pointee), remaining)
	)

	guard ioDataPacketCount.pointee > 0 else {
		return noErr
	}
	
	let sourceBufferSize = Int(UInt64(ioDataPacketCount.pointee) * audioConverterSettings.inputFilePacketMaxSize)
	if audioConverterSettings.sourceBuffer == nil {
		audioConverterSettings.sourceBuffer = UnsafeMutableRawPointer.allocate(byteCount: sourceBufferSize, alignment: MemoryLayout<UInt8>.alignment)
	}
	audioConverterSettings.sourceBuffer?.initializeMemory(as: UInt8.self, repeating: 0, count: sourceBufferSize)
	
	var outByteCount: UInt32 = 0
	
	var result = noErr
	audioConverterSettings.inputFilePacketDescriptions.withUnsafeMutableBufferPointer { descriptions in
		result = AudioFileReadPackets(
			audioConverterSettings.inputFile!,
			true,
			&outByteCount,
			descriptions.baseAddress, // <--- Must be baseAddress (index 0) so AudioFileReadPackets fills it from the start for this batch
			Int64(audioConverterSettings.inputFilePacketIndex),
			ioDataPacketCount,
			audioConverterSettings.sourceBuffer
		)
	}
	
	if result == kAudioFileEndOfFileError && ioDataPacketCount.pointee > 0 {
		result = noErr
	} else if result != noErr {
		return result
	}
	
	audioConverterSettings.inputFilePacketIndex += UInt64(ioDataPacketCount.pointee)
	bufferList[0].mData = audioConverterSettings.sourceBuffer
	bufferList[0].mDataByteSize = outByteCount
	if let outDataPacketDescription, !audioConverterSettings.inputFilePacketDescriptions.isEmpty {
		var outDataPacketDescription = outDataPacketDescription
		audioConverterSettings.inputFilePacketDescriptions.withUnsafeMutableBufferPointer { descriptions in
			outDataPacketDescription.pointee = descriptions.baseAddress
		}
	}
	
	return result
}

//MARK: main function
func convertMain() {
	// open input file
	let audioConverterSettings = MyAudioConverterSettings()
	let audioConverterSettingsPointer = Unmanaged.passUnretained(audioConverterSettings).toOpaque()
	let inputFileURL = NSURL(fileURLWithPath: kInputFileLocation)
	check(error: AudioFileOpenURL(
			inputFileURL,
			.readPermission,
			0,
			&audioConverterSettings.inputFile
		),
		description: "AudioFileOpenURL failed"
	)
	
	// get input format
	var propSize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
	check(error: AudioFileGetProperty(
			audioConverterSettings.inputFile!,
			kAudioFilePropertyDataFormat,
			&propSize,
			&audioConverterSettings.inputFormat
		),
		description: "Couldn't get file's data format"
	)
	
	// setup output file
	propSize = UInt32(MemoryLayout<UInt64>.size)
	check(error: AudioFileGetProperty(
			audioConverterSettings.inputFile!,
			kAudioFilePropertyAudioDataPacketCount,
			&propSize,
			&audioConverterSettings.inputFilePacketCount
		),
		description: "couldn't get file's packet count"
	)
	
	propSize = UInt32(MemoryLayout<UInt32>.size)
	check(error: AudioFileGetProperty(
			audioConverterSettings.inputFile!,
			kAudioFilePropertyMaximumPacketSize,
			&propSize,
			&audioConverterSettings.inputFilePacketMaxSize
		),
		description: "couldn't get file's max packet size"
	)
	
	// perform conversion
	audioConverterSettings.outputFormat.mSampleRate = 44100.0
	audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
	audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
	audioConverterSettings.outputFormat.mBytesPerPacket = 4
	audioConverterSettings.outputFormat.mFramesPerPacket = 1
	audioConverterSettings.outputFormat.mBytesPerFrame = 4
	audioConverterSettings.outputFormat.mChannelsPerFrame = 2
	audioConverterSettings.outputFormat.mBitsPerChannel = 16
	
	let outputURL = NSURL(fileURLWithPath: kOutputFileLocation)
	check(error: AudioFileCreateWithURL(
			outputURL,
			kAudioFileAIFFType,
			&audioConverterSettings.outputFormat,
			.eraseFile,
			&audioConverterSettings.outputFile
		),
		description: "AudioFileCreateWithURL failed"
	)
	
	print("Converting...")
	convert(settings: audioConverterSettings)
	
	AudioFileClose(audioConverterSettings.inputFile!)
	AudioFileClose(audioConverterSettings.outputFile!)
}

#Playground {
	print("Learning Core Audio - Chapter 6.1")
	//convertMain()
}
