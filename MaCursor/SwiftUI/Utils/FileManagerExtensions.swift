import Foundation

extension FileManager {
    
    @objc func findOrCreateDirectory(
        _ searchPathDirectory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask,
        appendPathComponent appendComponent: String?
    ) throws -> String {
        let paths = NSSearchPathForDirectoriesInDomains(searchPathDirectory, domainMask, true)
        
        guard var resolvedPath = paths.first else {
            throw NSError(
                domain: "DirectoryLocationDomain",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "No path found for directory in domain.",
                        comment: "Error when no path is found for a system directory"
                    ),
                    "NSSearchPathDirectory": searchPathDirectory.rawValue,
                    "NSSearchPathDomainMask": domainMask.rawValue
                ]
            )
        }
        
        if let appendComponent, !appendComponent.isEmpty {
            resolvedPath = (resolvedPath as NSString).appendingPathComponent(appendComponent)
        }
        
        try createDirectory(atPath: resolvedPath, withIntermediateDirectories: true, attributes: nil)
        
        return resolvedPath
    }
    
    @objc var applicationSupportDirectory: String {
        let executableName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "MaCursor"
        do {
            return try findOrCreateDirectory(
                .applicationSupportDirectory,
                in: .userDomainMask,
                appendPathComponent: executableName
            )
        } catch {
            NSLog("Unable to find or create application support directory:\n%@", error.localizedDescription)
            return ""
        }
    }
}
