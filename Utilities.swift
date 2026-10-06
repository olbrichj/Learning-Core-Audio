// Due to the nature of playgrounds this file is not picked up, so corresponding copies will be found in the chapters code

import CoreAudioTypes

extension AudioFormatID {
	var format: String {
		return withUnsafeBytes(of: self) { buffer in
			String(decoding: buffer, as: UTF8.self)
		}
	}
}
