#ifndef CJPEGLI_H
#define CJPEGLI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Encodes 8-bit RGBX pixels (4 bytes per pixel, the 4th ignored) as a progressive 4:4:4 JPEG.
/// `distance` is jpegli's butteraugli target: lower is better, 1.0 is roughly visually lossless.
/// Returns a malloc'd buffer the caller frees with free() and sets `outSize`, or NULL on failure.
uint8_t *_Nullable cjpegli_encode_rgbx(const uint8_t *_Nonnull pixels, int width, int height,
                                       size_t bytesPerRow, float distance,
                                       const uint8_t *_Nullable icc, size_t iccSize,
                                       size_t *_Nonnull outSize);

/// jpegli's own mapping from a libjpeg-style 0–100 quality to a distance.
float cjpegli_quality_to_distance(int quality);

#ifdef __cplusplus
}
#endif

#endif
