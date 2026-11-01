#include "CJpegli.h"

#include <csetjmp>
#include <cstdlib>
#include <vector>

#include "lib/jpegli/encode.h"

namespace {

// libjpeg-style errors call error_exit, which by default exits the process; jump back out instead
struct ErrorManager {
    jpeg_error_mgr base;
    std::jmp_buf jump;
};

void ErrorExit(j_common_ptr cinfo) {
    std::longjmp(reinterpret_cast<ErrorManager *>(cinfo->err)->jump, 1);
}

void IgnoreMessage(j_common_ptr) {}

struct Destination {
    unsigned char *data = nullptr;
    unsigned long size = 0;
};

}  // namespace

uint8_t *cjpegli_encode_rgbx(const uint8_t *pixels, int width, int height, size_t bytesPerRow,
                             float distance, const uint8_t *icc, size_t iccSize, size_t *outSize) {
    jpeg_compress_struct cinfo = {};
    ErrorManager errors = {};
    Destination destination;
    std::vector<JSAMPLE> row(static_cast<size_t>(width) * 3);

    cinfo.err = jpegli_std_error(&errors.base);
    errors.base.error_exit = ErrorExit;
    errors.base.output_message = IgnoreMessage;

    if (setjmp(errors.jump)) {
        jpegli_destroy_compress(&cinfo);
        std::free(destination.data);
        return nullptr;
    }

    jpegli_create_compress(&cinfo);
    jpegli_mem_dest(&cinfo, &destination.data, &destination.size);

    cinfo.image_width = static_cast<JDIMENSION>(width);
    cinfo.image_height = static_cast<JDIMENSION>(height);
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpegli_set_defaults(&cinfo);
    jpegli_set_distance(&cinfo, distance, TRUE);

    // Full-resolution chroma keeps saturated edges and text crisp
    for (int i = 0; i < cinfo.num_components; i++) {
        cinfo.comp_info[i].h_samp_factor = 1;
        cinfo.comp_info[i].v_samp_factor = 1;
    }

    jpegli_start_compress(&cinfo, TRUE);
    if (icc != nullptr && iccSize > 0) {
        jpegli_write_icc_profile(&cinfo, icc, static_cast<unsigned int>(iccSize));
    }

    JSAMPROW rows[] = {row.data()};
    while (cinfo.next_scanline < cinfo.image_height) {
        const uint8_t *source = pixels + cinfo.next_scanline * bytesPerRow;
        for (int x = 0; x < width; x++) {
            row[x * 3] = source[x * 4];
            row[x * 3 + 1] = source[x * 4 + 1];
            row[x * 3 + 2] = source[x * 4 + 2];
        }
        jpegli_write_scanlines(&cinfo, rows, 1);
    }

    jpegli_finish_compress(&cinfo);
    jpegli_destroy_compress(&cinfo);

    *outSize = destination.size;
    return destination.data;
}

float cjpegli_quality_to_distance(int quality) {
    return jpegli_quality_to_distance(quality);
}
