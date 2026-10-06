import Playgrounds

import Foundation
import AudioToolbox

func getInfo(for file: String) {
	let audioFilePath = NSString(string: file).expandingTildeInPath

	let audioUrl = URL(fileURLWithPath: audioFilePath)

	nonisolated(unsafe) var audioFile: AudioFileID!
	nonisolated(unsafe) var theErr: OSStatus = noErr

	theErr = AudioFileOpenURL(
		audioUrl as CFURL,
		.readPermission,
		.zero,
		&audioFile
	)
	assert(theErr == noErr)
	
	var dictionarySize: UInt32 = 0
	
	theErr = AudioFileGetPropertyInfo(
		audioFile,
		kAudioFilePropertyInfoDictionary,
		&dictionarySize,
		nil
	)
	assert(theErr == noErr)
	
	var dictionary: NSDictionary!
	
	theErr = withUnsafeMutablePointer(to: &dictionary) { dictPtr in
		AudioFileGetProperty(
			audioFile,
			kAudioFilePropertyInfoDictionary,
			&dictionarySize,
			UnsafeMutableRawPointer(dictPtr))
	}
	assert(theErr == noErr)
	
	print("Dictionary: \(String(describing: dictionary))")
	
	theErr = AudioFileClose(audioFile)
	assert(theErr == noErr)
}

#Playground {
	print("Learning Core Audio - Chapter 1")
	//getInfo(for:"~/Downloads/Assimil/Koreanisch ohne Mühe/ASSIMIL Korean/L005-LESSON.mp3")
}
