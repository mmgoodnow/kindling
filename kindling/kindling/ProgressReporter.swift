import Observation

@Observable
class ProgressReporter {
	var status: String? = nil
	var current: Int = 0
	var total: Int = 0

	func setTotal(_ total: Int) {
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
