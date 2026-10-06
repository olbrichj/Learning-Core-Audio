import Playgrounds
import AudioToolbox
import CoreAudioTypes
import Foundation

let SAMPLE_RATE = 44100.0
let DURATION = 5.0
let FILE_NAME_FORMAT = "%0.3f-square.aif"

func generateToneFile(hz: Double) {
	guard hz > 0 else { return }
	
	print("generation \(hz) hz tone")
	let fileName = String(format: FILE_NAME_FORMAT, hz)
	let currentPath = FileManager.default.currentDirectoryPath // FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
	let fileURL = URL(fileURLWithPath: currentPath).appendingPathComponent(fileName)
	print(fileURL.path)
	
	var asbd = AudioStreamBasicDescription()
	asbd.mSampleRate = SAMPLE_RATE
	asbd.mFormatID = kAudioFormatLinearPCM
	asbd.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
	asbd.mBitsPerChannel = 16
	asbd.mChannelsPerFrame = 1
	asbd.mFramesPerPacket = 1
	asbd.mBytesPerFrame = 2
	asbd.mBytesPerPacket = 2
	
	var audioFile: AudioFileID!
	var audioErr: OSStatus = noErr
	audioErr = AudioFileCreateWithURL(
		fileURL as NSURL,
		kAudioFileAIFFType,
		&asbd,
		.eraseFile,
		&audioFile
	)
	guard audioErr == noErr else { return }
	
	let maxSampleCount = SAMPLE_RATE * DURATION
	var sampleCount = 0
	var bytesToWrite: UInt32 = 2
	let wavelengthInSamples = SAMPLE_RATE / hz
	
	while sampleCount < Int(maxSampleCount) {
		for i in 0..<Int(wavelengthInSamples) {
			var sample: UInt16
			if i < Int(wavelengthInSamples / 2) {
				sample = UInt16(bitPattern: Int16.max).bigEndian
			} else {
				sample = UInt16(bitPattern: Int16.min).bigEndian
			}
			
			audioErr = AudioFileWriteBytes(
				audioFile,
				false,
				Int64(sampleCount*2),
				&bytesToWrite,
				&sample
			)
			guard audioErr == noErr else { return }
			
			sampleCount += 1
		}
	}
	audioErr = AudioFileClose(audioFile)
	guard audioErr == noErr else { return }
	print("wrote \(sampleCount) samples")
}

#Playground {
	print("Learning Core Audio - Chapter 2")
	//generateToneFile(hz: 4000)
}
