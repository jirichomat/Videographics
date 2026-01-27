//
//  ThumbnailCache.swift
//  Videographics
//
//  Lazy thumbnail loading with LRU eviction for memory efficiency

import Foundation
import UIKit
import SwiftUI

/// Cache key for identifying thumbnails
struct ThumbnailCacheKey: Hashable {
    let clipId: UUID
    let index: Int
}

/// Manages in-memory caching of thumbnail images with LRU eviction
@MainActor
@Observable
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    // MARK: - Configuration

    /// Maximum number of thumbnails to keep in memory
    private let maxCachedThumbnails = 100

    /// Maximum memory usage in bytes (approximately 50MB)
    private let maxMemoryBytes = 50 * 1024 * 1024

    // MARK: - State

    /// Cached UIImages keyed by clip ID and index
    private var cache: [ThumbnailCacheKey: UIImage] = [:]

    /// Access order for LRU eviction (most recent at the end)
    private var accessOrder: [ThumbnailCacheKey] = []

    /// Currently loading thumbnails to prevent duplicate loads
    private var loadingKeys: Set<ThumbnailCacheKey> = []

    /// Clips that are currently visible (for prefetching priority)
    private var visibleClipIds: Set<UUID> = []

    /// Approximate current memory usage
    private var estimatedMemoryUsage: Int = 0

    private init() {
        // Subscribe to memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }

    // MARK: - Public API

    /// Get a cached thumbnail image, or nil if not cached
    func getThumbnail(for clipId: UUID, at index: Int) -> UIImage? {
        let key = ThumbnailCacheKey(clipId: clipId, index: index)

        if let image = cache[key] {
            // Update access order for LRU
            updateAccessOrder(for: key)
            return image
        }

        return nil
    }

    /// Cache a thumbnail image
    func setThumbnail(_ image: UIImage, for clipId: UUID, at index: Int) {
        let key = ThumbnailCacheKey(clipId: clipId, index: index)

        // If already cached, just update access order
        if cache[key] != nil {
            updateAccessOrder(for: key)
            return
        }

        // Estimate memory for this image
        let imageMemory = estimateMemory(for: image)

        // Evict if necessary before adding
        evictIfNeeded(forNewImageMemory: imageMemory)

        // Add to cache
        cache[key] = image
        accessOrder.append(key)
        estimatedMemoryUsage += imageMemory
    }

    /// Load thumbnails for a clip asynchronously (decodes from Data)
    func loadThumbnails(for clip: VideoClip, indices: Range<Int>) async {
        let thumbnailsData = clip.thumbnails
        guard !thumbnailsData.isEmpty else { return }

        for index in indices {
            guard index < thumbnailsData.count else { continue }

            let key = ThumbnailCacheKey(clipId: clip.id, index: index)

            // Skip if already cached or loading
            if cache[key] != nil || loadingKeys.contains(key) {
                continue
            }

            loadingKeys.insert(key)

            // Decode on background thread
            let data = thumbnailsData[index]
            if let image = await decodeImage(from: data) {
                setThumbnail(image, for: clip.id, at: index)
            }

            loadingKeys.remove(key)
        }
    }

    /// Mark a clip as visible (prioritizes its thumbnails)
    func markClipVisible(_ clipId: UUID) {
        visibleClipIds.insert(clipId)
    }

    /// Mark a clip as no longer visible
    func markClipHidden(_ clipId: UUID) {
        visibleClipIds.remove(clipId)
    }

    /// Prefetch thumbnails for clips near the visible area
    func prefetchThumbnails(for clips: [VideoClip]) {
        Task {
            for clip in clips {
                let thumbnailCount = clip.thumbnails.count
                guard thumbnailCount > 0 else { continue }

                // Load all thumbnails for nearby clips
                await loadThumbnails(for: clip, indices: 0..<thumbnailCount)
            }
        }
    }

    /// Evict thumbnails for a specific clip
    func evictThumbnails(for clipId: UUID) {
        let keysToRemove = cache.keys.filter { $0.clipId == clipId }

        for key in keysToRemove {
            if let image = cache.removeValue(forKey: key) {
                estimatedMemoryUsage -= estimateMemory(for: image)
            }
            accessOrder.removeAll { $0 == key }
        }
    }

    /// Clear all cached thumbnails
    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        loadingKeys.removeAll()
        estimatedMemoryUsage = 0
    }

    /// Get cache statistics for debugging
    var cacheStats: (count: Int, memoryMB: Double) {
        (cache.count, Double(estimatedMemoryUsage) / (1024 * 1024))
    }

    // MARK: - Private Methods

    private func updateAccessOrder(for key: ThumbnailCacheKey) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
    }

    private func evictIfNeeded(forNewImageMemory newMemory: Int) {
        // Evict while over limits
        while (cache.count >= maxCachedThumbnails ||
               estimatedMemoryUsage + newMemory > maxMemoryBytes) &&
              !accessOrder.isEmpty {

            // Find oldest non-visible thumbnail to evict
            if let keyToEvict = findLRUEvictionCandidate() {
                evictKey(keyToEvict)
            } else {
                // If all thumbnails are visible, evict the oldest anyway
                if let keyToEvict = accessOrder.first {
                    evictKey(keyToEvict)
                } else {
                    break
                }
            }
        }
    }

    private func findLRUEvictionCandidate() -> ThumbnailCacheKey? {
        // Prefer evicting non-visible clips first
        for key in accessOrder {
            if !visibleClipIds.contains(key.clipId) {
                return key
            }
        }
        // If all are visible, return oldest
        return accessOrder.first
    }

    private func evictKey(_ key: ThumbnailCacheKey) {
        if let image = cache.removeValue(forKey: key) {
            estimatedMemoryUsage -= estimateMemory(for: image)
        }
        accessOrder.removeAll { $0 == key }
    }

    private func estimateMemory(for image: UIImage) -> Int {
        // Approximate: width * height * 4 bytes (RGBA)
        let size = image.size
        let scale = image.scale
        return Int(size.width * scale * size.height * scale * 4)
    }

    private func decodeImage(from data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = UIImage(data: data)
                continuation.resume(returning: image)
            }
        }
    }

    private func handleMemoryWarning() {
        // Evict half the cache on memory warning
        let targetCount = cache.count / 2

        while cache.count > targetCount && !accessOrder.isEmpty {
            if let keyToEvict = findLRUEvictionCandidate() {
                evictKey(keyToEvict)
            } else {
                break
            }
        }
    }
}
