//
//  FileStorageService.swift
//  Videographics
//

import Foundation
import AVFoundation

actor FileStorageService {
    static let shared = FileStorageService()

    private let fileManager = FileManager.default

    private var projectsDirectory: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectsURL = documentsURL.appendingPathComponent("Projects", isDirectory: true)

        if !fileManager.fileExists(atPath: projectsURL.path) {
            try? fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        }

        return projectsURL
    }

    /// Get the directory for a specific project
    func projectDirectory(for projectId: UUID) -> URL {
        let projectURL = projectsDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)

        if !fileManager.fileExists(atPath: projectURL.path) {
            try? fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        }

        return projectURL
    }

    /// Get the media directory for a project
    func mediaDirectory(for projectId: UUID) -> URL {
        let mediaURL = projectDirectory(for: projectId).appendingPathComponent("Media", isDirectory: true)

        if !fileManager.fileExists(atPath: mediaURL.path) {
            try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        }

        return mediaURL
    }

    /// Copy a media file to the project's media directory
    func copyMediaToProject(sourceURL: URL, projectId: UUID) async throws -> URL {
        let mediaDir = mediaDirectory(for: projectId)
        let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = mediaDir.appendingPathComponent(fileName)

        // If the source URL is a security-scoped resource, we need to handle it appropriately
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Delete a media file
    func deleteMedia(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Delete all media for a project
    func deleteProjectMedia(projectId: UUID) throws {
        let projectDir = projectDirectory(for: projectId)
        if fileManager.fileExists(atPath: projectDir.path) {
            try fileManager.removeItem(at: projectDir)
        }
    }

    /// Get the size of a file
    func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }
}
