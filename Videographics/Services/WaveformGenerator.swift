//
//  WaveformGenerator.swift
//  Videographics
//

import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Represents waveform data extracted from an audio source
struct WaveformData: Codable, Sendable {
    /// Normalized amplitude samples (0.0 to 1.0)
    let samples: [Float]

    /// Duration of the source audio
    let duration: TimeInterval

    /// Number of samples per second (for time mapping)
    let samplesPerSecond: Double

    /// Get sample index for a given time
    func sampleIndex(for time: TimeInterval) -> Int {
        let index = Int(time * samplesPerSecond)
        return min(max(0, index), samples.count - 1)
    }

    /// Get samples within a time range
    func samples(from startTime: TimeInterval, to endTime: TimeInterval) -> ArraySlice<Float> {
        let startIndex = sampleIndex(for: startTime)
        let endIndex = sampleIndex(for: endTime)
        return samples[startIndex...endIndex]
    }
}

/// Service that extracts audio sample data from video/audio files and generates waveform visualizations
actor WaveformGenerator {
    static let shared = WaveformGenerator()

    // MARK: - Configuration

    /// Target samples per second for waveform visualization
    /// Higher = more detail, lower = faster/smaller
    private let targetSamplesPerSecond: Double = 50

    /// Maximum number of cached waveforms
    private let maxCacheSize = 20

    // MARK: - Cache

    /// In-memory cache keyed by asset URL
    private var cache: [String: WaveformData] = [:]

    /// Order of cache entries for LRU eviction
    private var cacheOrder: [String] = []

    // MARK: - Public API

    /// Generate waveform data for an audio or video asset
    /// - Parameters:
    ///   - url: URL of the audio/video file
    ///   - samplesPerSecond: Optional override for samples per second (default: 50)
    /// - Returns: WaveformData containing normalized amplitude samples
    func generateWaveform(for url: URL, samplesPerSecond: Double? = nil) async throws -> WaveformData {
        let cacheKey = url.absoluteString

        // Check cache first
        if let cached = cache[cacheKey] {
            // Move to end of LRU order
            if let index = cacheOrder.firstIndex(of: cacheKey) {
                cacheOrder.remove(at: index)
                cacheOrder.append(cacheKey)
            }
            return cached
        }

        // Generate new waveform
        let targetSPS = samplesPerSecond ?? targetSamplesPerSecond
        let waveform = try await extractWaveform(from: url, samplesPerSecond: targetSPS)

        // Cache the result
        cacheWaveform(waveform, forKey: cacheKey)

        return waveform
    }

    /// Clear a specific entry from the cache
    func clearCache(for url: URL) {
        let key = url.absoluteString
        cache.removeValue(forKey: key)
        if let index = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: index)
        }
    }

    /// Clear all cached waveforms
    func clearAllCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// Check if waveform is cached for a URL
    func isCached(url: URL) -> Bool {
        return cache[url.absoluteString] != nil
    }

    // MARK: - Private Implementation

    private func extractWaveform(from url: URL, samplesPerSecond: Double) async throws -> WaveformData {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Load asset properties
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = tracks.first else {
            throw WaveformError.noAudioTrack
        }

        // Get audio format details
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw WaveformError.invalidAudioFormat
        }

        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let sourceSampleRate = audioStreamBasicDescription?.pointee.mSampleRate ?? 44100

        // Calculate how many source samples per output sample
        let durationSeconds = duration.seconds
        let totalOutputSamples = Int(durationSeconds * samplesPerSecond)

        guard totalOutputSamples > 0 else {
            throw WaveformError.invalidDuration
        }

        // Set up asset reader
        let reader = try AVAssetReader(asset: asset)

        // Configure output settings for raw PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            throw WaveformError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        guard reader.startReading() else {
            throw WaveformError.readerFailed(reader.error)
        }

        // Read and process samples
        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(durationSeconds * sourceSampleRate))

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?

                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &length,
                    dataPointerOut: &dataPointer
                )

                if status == kCMBlockBufferNoErr, let data = dataPointer {
                    // Convert Int16 samples to Float
                    let int16Pointer = data.withMemoryRebound(to: Int16.self, capacity: length / 2) { $0 }
                    let sampleCount = length / 2

                    for i in 0..<sampleCount {
                        let sample = Float(int16Pointer[i]) / Float(Int16.max)
                        allSamples.append(abs(sample))
                    }
                }
            }
        }

        // Check reader status
        if reader.status == .failed {
            throw WaveformError.readerFailed(reader.error)
        }

        // Downsample to target resolution
        let downsampled = downsample(samples: allSamples, toCount: totalOutputSamples)

        return WaveformData(
            samples: downsampled,
            duration: durationSeconds,
            samplesPerSecond: samplesPerSecond
        )
    }

    /// Downsample audio samples to a target count using peak detection
    private func downsample(samples: [Float], toCount targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard targetCount > 0 else { return [] }

        if samples.count <= targetCount {
            // Pad with zeros if needed, or return as-is
            return samples
        }

        let samplesPerBucket = Float(samples.count) / Float(targetCount)
        var result = [Float](repeating: 0, count: targetCount)

        for i in 0..<targetCount {
            let startIndex = Int(Float(i) * samplesPerBucket)
            let endIndex = min(Int(Float(i + 1) * samplesPerBucket), samples.count)

            guard startIndex < endIndex else {
                result[i] = 0
                continue
            }

            // Use peak value for this bucket (better visual representation)
            var maxValue: Float = 0
            for j in startIndex..<endIndex {
                maxValue = max(maxValue, samples[j])
            }
            result[i] = maxValue
        }

        // Normalize to 0.0-1.0 range
        if let maxSample = result.max(), maxSample > 0 {
            for i in 0..<result.count {
                result[i] = result[i] / maxSample
            }
        }

        return result
    }

    /// Cache a waveform with LRU eviction
    private func cacheWaveform(_ waveform: WaveformData, forKey key: String) {
        // Evict oldest if at capacity
        while cacheOrder.count >= maxCacheSize {
            if let oldest = cacheOrder.first {
                cache.removeValue(forKey: oldest)
                cacheOrder.removeFirst()
            }
        }

        cache[key] = waveform
        cacheOrder.append(key)
    }
}

// MARK: - Errors

enum WaveformError: Error, LocalizedError {
    case noAudioTrack
    case invalidAudioFormat
    case invalidDuration
    case cannotAddReaderOutput
    case readerFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in the asset"
        case .invalidAudioFormat:
            return "Could not read audio format information"
        case .invalidDuration:
            return "Asset has invalid or zero duration"
        case .cannotAddReaderOutput:
            return "Cannot configure audio reader"
        case .readerFailed(let error):
            if let error = error {
                return "Failed to read audio: \(error.localizedDescription)"
            }
            return "Failed to read audio samples"
        }
    }
}
