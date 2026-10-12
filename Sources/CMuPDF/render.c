#include "shim.h"

fz_pixmap *nanopdf_render_page_bbox(fz_context *ctx, fz_page *page, fz_matrix ctm, fz_irect bbox, int alpha, fz_cookie *cookie) {
    fz_pixmap *pix = NULL;
    fz_device *dev = NULL;

    fz_var(pix);
    fz_var(dev);

    fz_try(ctx) {
        pix = (fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), bbox, NULL, alpha));
        fz_clear_pixmap_with_value(ctx, pix, 0xFF);
        dev = fz_new_draw_device(ctx, ctm, pix);
        fz_run_page(ctx, page, dev, ctm, cookie);
        fz_close_device(ctx, dev);
    }
    fz_always(ctx) {
        fz_drop_device(ctx, dev);
    }
    fz_catch(ctx) {
        fz_drop_pixmap(ctx, pix);
        pix = NULL;
    }

    return pix;
}
