// Due to the nature of playgrounds this file is not picked up, so corresponding copies will be found in the chapters code

import CoreAudioTypes

extension AudioFormatID {
	var format: String {
		return withUnsafeBytes(of: self) { buffer in
			String(decoding: buffer, as: UTF8.self)
		}
	}
}

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
