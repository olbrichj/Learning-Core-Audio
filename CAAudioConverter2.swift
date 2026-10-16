import Playgrounds

import AudioToolbox
import CoreAudioTypes

let kInputFileLocation = "<fully qualified file path>"
let kOutputFileLocation = "<fully qualified file path>.aif"

//MARK: user data
final class MyAudioConverterSettings {
	var outputFormat = AudioStreamBasicDescription()
	var inputFile: ExtAudioFileRef?
	var outputFile: AudioFileID?
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
	let outputBufferSize: UInt32 = 32 * 1024
	let sizePerPacket = settings.outputFormat.mBytesPerPacket
	let packetsPerBuffer = outputBufferSize / sizePerPacket
	
	let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(outputBufferSize))
	var outputFilePacketPosition: UInt32 = 0
	
	while true {
		let convertedData = AudioBufferList.allocate(maximumBuffers: 1)
		convertedData[0] = AudioBuffer(mNumberChannels: settings.outputFormat.mChannelsPerFrame, mDataByteSize: outputBufferSize, mData: outputBuffer)
		
		var frameCount = packetsPerBuffer
		check(error: ExtAudioFileRead(
				settings.inputFile!,
				&frameCount,
				convertedData.unsafeMutablePointer
			),
			description: "Coudn't read from input file"
		)
		
		guard frameCount > 0 else {
			print("Done reading from file")
			return
		}
		
		var packetsToWrite = frameCount

		check(error: AudioFileWritePackets(
				settings.outputFile!,
				false,
				convertedData[0].mDataByteSize,
				nil,
				Int64(outputFilePacketPosition),
				&packetsToWrite,
				convertedData[0].mData!
			),
			description: "Couldn't write packets to file"
		)

		outputFilePacketPosition += UInt32(packetsToWrite)
	}
}

//MARK: main function
func convertMain() {
	// open input file
	let audioConverterSettings = MyAudioConverterSettings()
	
	let inputFileURL = NSURL(fileURLWithPath: kInputFileLocation)
	check(error: ExtAudioFileOpenURL(
			inputFileURL,
			&audioConverterSettings.inputFile
		),
		  description: "ExtAudioFileOpenURL failed"
	)
	
	// Setup output file
	audioConverterSettings.outputFormat.mSampleRate = 44100.0
	audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
	audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
	audioConverterSettings.outputFormat.mBytesPerPacket = 4
	audioConverterSettings.outputFormat.mFramesPerPacket = 1
	audioConverterSettings.outputFormat.mBytesPerFrame = 4
	audioConverterSettings.outputFormat.mChannelsPerFrame = 2
	audioConverterSettings.outputFormat.mBitsPerChannel = 16
	
	let outputFileURL = NSURL(fileURLWithPath: kOutputFileLocation)
	check(error: AudioFileCreateWithURL(
			outputFileURL,
			kAudioFileAIFFType,
			&audioConverterSettings.outputFormat,
				.eraseFile, &audioConverterSettings.outputFile
		),
		description: "AudioFileCreateWithURL failed"
	)
	
	check(error: ExtAudioFileSetProperty(
			audioConverterSettings.inputFile!,
			kExtAudioFileProperty_ClientDataFormat,
			UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
			&audioConverterSettings.outputFormat
		),
		description: "Couldn't set client data format on input ext file"
	)
	
	// perform conversion
	print("Converting...")
	convert(settings: audioConverterSettings)
	
	ExtAudioFileDispose(audioConverterSettings.inputFile!)
	AudioFileClose(audioConverterSettings.outputFile!)
}

#Playground {
	print("Learning Core Audio - Chapter 6.2")
	//convertMain()
}
