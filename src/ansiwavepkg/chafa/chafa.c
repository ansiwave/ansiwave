#include <chafa.h>
#include <stdio.h>

#define N_CHANNELS 4

GString* image_to_ansi(guint8 *pixels, gint width, gint height, gint out_width)
{

    ChafaSymbolMap *symbol_map;
    ChafaCanvasConfig *config;
    ChafaCanvas *canvas;
    GString *gs;

    /* Specify the symbols we want */
    symbol_map = chafa_symbol_map_new ();
    chafa_symbol_map_add_by_tags (symbol_map, CHAFA_SYMBOL_TAG_BLOCK);

    /* Set up a configuration with the symbols and the canvas size in characters */
    config = chafa_canvas_config_new ();
    float fwidth = width;
    float fheight = height;
    float ratio = fheight / fwidth;
    chafa_canvas_config_set_geometry (config, out_width, ratio * (out_width/2));
    chafa_canvas_config_set_symbol_map (config, symbol_map);

    /* Create canvas */
    canvas = chafa_canvas_new (config);

    /* Draw pixels and build ANSI string */
    chafa_canvas_draw_all_pixels (canvas,
                                  CHAFA_PIXEL_RGBA8_UNASSOCIATED,
                                  pixels,
                                  width,
                                  height,
                                  width * N_CHANNELS);
    gs = chafa_canvas_build_ansi (canvas);

    /* Free resources */
    chafa_canvas_unref (canvas);
    chafa_canvas_config_unref (config);
    chafa_symbol_map_unref (symbol_map);

    return gs;
}
