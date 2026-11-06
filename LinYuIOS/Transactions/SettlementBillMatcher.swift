import Foundation
import CoreFoundation

/// SettlementEngine.matchBill's identifier-first lookup. The original time-only fallback
/// is constrained here so one meter's bill cannot clear another meter's pending settlement.
enum SettlementBillMatcher {
    static func match(_ bills: [[String: Any]], orderNo: String, snCode: String,
                      startedAt: Date, closedAt: Date) -> [String: Any]? {
        func sameDevice(_ bill: [String: Any]) -> Bool {
            guard let serial = text(bill["deviceSnCode"]) ?? text(bill["snCode"]) else { return true }
            return !snCode.isEmpty && serial == snCode
        }
        func unique(_ values: [[String: Any]]) -> [String: Any]? {
            guard values.count == 1, let bill = values.first, sameDevice(bill) else { return nil }
            return bill
        }
        guard !orderNo.isEmpty else { return nil }
        let exact = bills.filter { text($0["orderNo"]) == orderNo }
        if !exact.isEmpty { return unique(exact) }
        let legacyID = bills.filter { text($0["orderNo"]) == nil && text($0["orderId"]) == orderNo }
        if !legacyID.isEmpty { return unique(legacyID) }

        guard !snCode.isEmpty, startedAt.timeIntervalSince1970 > 0, closedAt >= startedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        let candidates = bills.filter { bill in
            // A different explicit order number is a contradiction, never a time fallback.
            guard text(bill["orderNo"]) == nil,
                  (text(bill["deviceSnCode"]) ?? text(bill["snCode"])) == snCode,
                  let raw = text(bill["consumeDate"]), let date = formatter.date(from: raw) else { return false }
            // Retain the original three-minute allowance before open confirmation;
            // stop the range at this closure, instead of accepting arbitrarily later orders.
            return date >= startedAt.addingTimeInterval(-180) && date <= closedAt
        }
        return unique(candidates)
    }

    static func responseMatches(_ data: [String: Any]?, orderNo: String, snCode: String) -> Bool {
        guard let data else { return false }
        if let number = text(data["orderNo"]), number != orderNo { return false }
        if let serial = text(data["deviceSnCode"]) ?? text(data["snCode"]), serial != snCode { return false }
        return true
    }

    private static func text(_ value: Any?) -> String? {
        let result: String?
        if let string = value as? String { result = string }
        else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { result = number.stringValue }
        else { result = nil }
        return result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? result : nil
    }
}
