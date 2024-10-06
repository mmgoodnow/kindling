import Network
import Observation

@Observable
class ProgressReporter {
	var status: String? = nil
	var current: Int = 0
	var total: Int = 0

	func start(_ total: Int) {
		current = 0
		self.total = total
	}

	func tick(_ status: String) {
		current += 1
		self.status = status
	}

	func complete(_ status: String) {
		current = total
		self.status = status
	}

	func reset() {
		status = nil
		current = 0
		total = 0
	}

	var progress: Double? {
		guard total > 0 else { return nil }
		return Double(current) / Double(total)
	}
}

enum ConnectionState {
	case idle
	case loading
	case failed
	case ready
}

@Observable
class StateReporter {
	var registrationState: ConnectionState = .idle
	var nwConnectionState: NWConnection.State = .setup

	var state: ConnectionState {
		switch nwConnectionState {
		case .failed:
			return .failed
		case .ready:
			return registrationState
		case .cancelled:
			return .idle
		default:
			return .loading
		}
	}
}
