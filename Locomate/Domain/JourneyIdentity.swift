import Foundation

/// A dated run has one identity across responses, caches, and side effects.
public enum JourneyIdentity {
    public enum ValidationError: Error, LocalizedError {
        case invalidRequest, mismatchedResponse
        public var errorDescription: String? {
            switch self {
            case .invalidRequest: "The journey number or origin date is invalid."
            case .mismatchedResponse: "The service returned a different dated journey."
            }
        }
    }

    public static func validate(_ journey: Journey, trainNumber: String, originDate: String) throws {
        guard Routes.isValidTrainNumber(trainNumber),
              Routes.isValidCalendarDate(originDate) else { throw ValidationError.invalidRequest }
        guard journey.trainNumber == trainNumber, journey.travelDate == originDate,
              journey.id == "run:\(trainNumber):\(originDate)" else {
            throw ValidationError.mismatchedResponse
        }
    }
}
