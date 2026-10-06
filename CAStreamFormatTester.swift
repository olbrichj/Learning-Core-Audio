import Playgrounds

import AudioToolbox
import CoreAudioTypes
import Foundation

func determineStreamDescriptions() {
	var fileTypeAndFormat = AudioFileTypeAndFormatID()
	fileTypeAndFormat.mFileType = kAudioFileWAVEType
	fileTypeAndFormat.mFormatID = kAudioFormatLinearPCM
	
	var audioErr = noErr
	var infoSize: UInt32 = 0
	
	audioErr = AudioFileGetGlobalInfoSize(
		kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
		UInt32(MemoryLayout<AudioFileTypeAndFormatID>.size),
		&fileTypeAndFormat,
		&infoSize
	)
	guard audioErr == noErr else { return }
	
	let count = Int(infoSize) / MemoryLayout<AudioStreamBasicDescription>.size
	var asbds = Array(repeating: AudioStreamBasicDescription(), count: count)
	
	audioErr = AudioFileGetGlobalInfo(
		kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
		UInt32(MemoryLayout<AudioFileTypeAndFormatID>.size),
		&fileTypeAndFormat,
		&infoSize,
		&asbds
	)
	guard audioErr == noErr else { return }
	
	var asbdCount = infoSize / UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
	
	for i in 0..<Int(asbdCount) {
		let asbd = asbds[i]
		let formatString = asbd.mFormatID.bigEndian.format
		
		
		print("mFormatId: \(formatString), mFormatFlags: \(asbd.mFormatFlags), mBitsPerChannel: \(asbd.mBitsPerChannel)")
	}
}

extension AudioFormatID {
	var format: String {
		return withUnsafeBytes(of: self) { buffer in
			String(decoding: buffer, as: UTF8.self)
		}
	}
}

#Playground {
	print("Learning Core Audio - Chapter 3")
	//determineStreamDescriptions()
}
