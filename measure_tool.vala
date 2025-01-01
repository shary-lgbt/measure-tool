using GLib;

public class MeasureTool : Gtk.Window {
    private bool is_measuring = false;
    private bool is_moving = false;
    private bool is_resizing = false;
    private double start_x = 0;
    private double start_y = 0;
    private double current_x = 0;
    private double current_y = 0;
    private int last_width = 0;
    private int last_height = 0;
    private double drag_offset_x = 0;
    private double drag_offset_y = 0;
    private int resize_handle = 0;
    private const int HANDLE_SIZE = 10;
    private bool is_picking_color = false;
    private string current_hex_color = "";
    private string current_rgb_color = "";
    private const int MAGNIFIER_SIZE = 200;
    private const int MAGNIFIER_ZOOM = 4;
    private string color_history_file;
    private const int MAX_COLORS = 50;
    
    public MeasureTool() {
        Object(
            title: "Herramienta de Medición",
            window_position: Gtk.WindowPosition.CENTER
        );
        
        // Crear y establecer el icono
        try {
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 64, 64);
            var cr = new Cairo.Context(surface);
            
            // Fondo negro
            cr.set_source_rgb(0, 0, 0);
            cr.rectangle(0, 0, 64, 64);
            cr.fill();
            
            // Dibujar mira en blanco
            cr.set_source_rgb(1, 1, 1);
            cr.set_line_width(2);
            
            // Línea horizontal
            cr.move_to(16, 32);
            cr.line_to(48, 32);
            
            // Línea vertical
            cr.move_to(32, 16);
            cr.line_to(32, 48);
            
            // Círculo central
            cr.arc(32, 32, 4, 0, 2 * Math.PI);
            
            cr.stroke();
            
            // Crear pixbuf desde la superficie
            var pixbuf = Gdk.pixbuf_get_from_surface(surface, 0, 0, 64, 64);
            this.set_icon(pixbuf);
            
            pixbuf.save(GLib.Environment.get_home_dir() + "/measure-tool.png", "png");
        } catch (Error e) {
            stderr.printf("Error al crear el icono: %s\n", e.message);
        }
        
        // Eliminar decoraciones de la ventana
        this.decorated = false;
        
        // Hacer la ventana transparente
        this.set_visual(this.get_screen().get_rgba_visual());
        this.app_paintable = true;
        
        // Configurar la ventana para que esté siempre visible
        this.set_keep_above(true);
        this.maximize();
        
        var drawing_area = new Gtk.DrawingArea();
        drawing_area.draw.connect(on_draw);
        
        // Configurar eventos del mouse
        var events = Gdk.EventMask.BUTTON_PRESS_MASK | 
                    Gdk.EventMask.BUTTON_RELEASE_MASK |
                    Gdk.EventMask.POINTER_MOTION_MASK |
                    Gdk.EventMask.POINTER_MOTION_HINT_MASK;
        drawing_area.add_events((int)events);
        
        drawing_area.button_press_event.connect(on_button_press);
        drawing_area.button_release_event.connect(on_button_release);
        drawing_area.motion_notify_event.connect((event) => {
            if (is_picking_color) {
                this.queue_draw();
                return true;
            }
            return on_motion(event);
        });
        
        this.add(drawing_area);
        
        color_history_file = Path.build_filename(Environment.get_home_dir(), "Escritorio", "color_history.txt");
        
        // Modificar eventos de teclado
        this.key_press_event.connect((event) => {
            if (event.keyval == Gdk.Key.Escape) {
                this.destroy();
                return true;
            }
            
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                if (event.keyval == Gdk.Key.c || event.keyval == Gdk.Key.C) {
                    copy_dimensions();
                    return true;
                }
                if (event.keyval == Gdk.Key.s || event.keyval == Gdk.Key.S) {
                    take_screenshot();
                    return true;
                }
            }
            
            // Activar color picker con Alt
            if (event.keyval == Gdk.Key.Alt_L || event.keyval == Gdk.Key.Alt_R) {
                is_picking_color = true;
                this.queue_draw();
                return true;
            }
            
            return false;
        });
        
        this.key_release_event.connect((event) => {
            if (event.keyval == Gdk.Key.Alt_L || event.keyval == Gdk.Key.Alt_R) {
                // Al soltar Alt, copiar el color actual
                if (current_hex_color != "") {
                    var clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
                    clipboard.set_text(current_hex_color, -1);
                    save_color(current_hex_color, current_rgb_color);
                    show_copy_notification("Color copiado: " + current_hex_color);
                }
                is_picking_color = false;
                this.queue_draw();
                return true;
            }
            return false;
        });
    }
    
    private void copy_dimensions() {
        if (last_width == 0 && last_height == 0) {
            return;
        }
        
        string dimensions = @"Ancho: $(last_width)px\nAlto: $(last_height)px";
        var clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(dimensions, -1);
        
        // Mostrar una notificación
        var notification = new Gtk.Window(Gtk.WindowType.POPUP);
        notification.set_default_size(200, 40);
        
        var label = new Gtk.Label("¡Dimensiones copiadas!");
        label.margin = 10;
        notification.add(label);
        
        // Posicionar la notificación
        var screen = this.get_screen();
        var monitor = screen.get_primary_monitor();
        var workarea = screen.get_monitor_workarea(monitor);
        
        notification.move(
            workarea.x + (workarea.width - 200) / 2,
            workarea.y + (workarea.height - 40) / 2
        );
        
        notification.show_all();
        
        // Cerrar la notificación después de 2 segundos
        GLib.Timeout.add(2000, () => {
            notification.destroy();
            return false;
        });
    }
    
    private void take_screenshot() {
        if (current_x == start_x || current_y == start_y) {
            return; // No hay área seleccionada
        }
        
        try {
            // Obtener las coordenadas del área
            int x = (int)double.min(start_x, current_x);
            int y = (int)double.min(start_y, current_y);
            int width = (int)Math.fabs(current_x - start_x);
            int height = (int)Math.fabs(current_y - start_y);
            
            // Ocultar temporalmente la ventana para la captura
            this.hide();
            
            // Esperar a que la ventana se oculte completamente
            while (Gtk.events_pending()) {
                Gtk.main_iteration();
            }
            Thread.usleep(200000); // Esperar 200ms para asegurar que la pantalla se actualice
            
            // Forzar actualización de la pantalla
            var root_window = screen.get_root_window();
            root_window.process_updates(true);
            
            // Tomar la captura del área desde la ventana raíz
            var screenshot = Gdk.pixbuf_get_from_window(
                root_window,
                x, y,
                width, height
            );
            
            // Mostrar la ventana nuevamente
            this.show();
            
            // Generar nombre de archivo único
            string timestamp = new DateTime.now_local().format("%Y%m%d_%H%M%S");
            string filename = @"screenshot_$(timestamp).png";
            string filepath = Path.build_filename(Environment.get_home_dir(), "Imágenes", filename);
            
            // Asegurarse de que el directorio existe
            File directory = File.new_for_path(Path.build_filename(Environment.get_home_dir(), "Imágenes"));
            if (!directory.query_exists()) {
                directory.make_directory_with_parents();
            }
            
            // Guardar la captura
            screenshot.save(filepath, "png");
            
            // Mostrar notificación
            var notification = new Gtk.Window(Gtk.WindowType.POPUP);
            notification.set_default_size(250, 40);
            
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
            box.margin = 10;
            
            var label = new Gtk.Label("¡Captura guardada!");
            label.margin = 5;
            box.add(label);
            
            var path_label = new Gtk.Label(filepath);
            path_label.margin = 5;
            path_label.set_line_wrap(true);
            box.add(path_label);
            
            notification.add(box);
            
            // Posicionar la notificación
            var workarea = screen.get_monitor_workarea(screen.get_primary_monitor());
            notification.move(
                workarea.x + (workarea.width - 250) / 2,
                workarea.y + (workarea.height - 80) / 2
            );
            
            notification.show_all();
            
            // Cerrar la notificación después de 2 segundos
            GLib.Timeout.add(2000, () => {
                notification.destroy();
                return false;
            });
            
        } catch (Error e) {
            stderr.printf("Error al guardar la captura: %s\n", e.message);
            
            // Asegurarse de que la ventana se muestre en caso de error
            this.show();
            
            // Mostrar notificación de error
            var error_notification = new Gtk.Window(Gtk.WindowType.POPUP);
            error_notification.set_default_size(200, 40);
            
            var label = new Gtk.Label("Error al guardar la captura");
            label.margin = 10;
            error_notification.add(label);
            
            error_notification.show_all();
            
            GLib.Timeout.add(2000, () => {
                error_notification.destroy();
                return false;
            });
        }
    }
    
    private bool on_draw(Cairo.Context cr) {
        cr.set_source_rgba(0, 0, 0, 0);
        cr.set_operator(Cairo.Operator.SOURCE);
        cr.paint();
        cr.set_operator(Cairo.Operator.OVER);
        
        if (current_x != start_x || current_y != start_y) {
            // Dibujar líneas del rectángulo
            cr.set_source_rgba(1, 0, 0, 0.8);
            cr.set_line_width(1);
            
            // Dibujar el rectángulo completo
            cr.move_to(start_x, start_y);
            cr.line_to(current_x, start_y);
            cr.line_to(current_x, current_y);
            cr.line_to(start_x, current_y);
            cr.line_to(start_x, start_y);
            cr.stroke();
            
            // Dibujar manejadores de redimensionamiento
            cr.set_source_rgba(1, 1, 1, 0.8);
            draw_resize_handle(cr, start_x, start_y);
            draw_resize_handle(cr, current_x, start_y);
            draw_resize_handle(cr, current_x, current_y);
            draw_resize_handle(cr, start_x, current_y);
            
            // Dibujar líneas guía extendidas
            cr.set_source_rgba(1, 0, 0, 0.4);  // Rojo más transparente
            cr.set_dash({5, 5}, 0);  // Línea punteada
            
            // Líneas horizontales extendidas
            cr.move_to(0, start_y);
            cr.line_to(screen.get_width(), start_y);
            cr.move_to(0, current_y);
            cr.line_to(screen.get_width(), current_y);
            
            // Líneas verticales extendidas
            cr.move_to(start_x, 0);
            cr.line_to(start_x, screen.get_height());
            cr.move_to(current_x, 0);
            cr.line_to(current_x, screen.get_height());
            cr.stroke();
            
            // Resetear el estilo de línea
            cr.set_dash(null, 0);
            
            // Mostrar dimensiones
            var width = (int)Math.fabs(current_x - start_x);
            var height = (int)Math.fabs(current_y - start_y);
            
            // Preparar el texto
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size(12);
            
            string dimensions_text = @"Ancho: $width px\nAlto: $height px";
            
            // Calcular posición del texto
            double text_x = current_x + 10;
            double text_y = current_y + 10;
            
            // Ajustar posición si está cerca de los bordes
            if (text_x + 100 > screen.get_width()) {
                text_x = current_x - 110;
            }
            if (text_y + 30 > screen.get_height()) {
                text_y = current_y - 30;
            }
            
            // Obtener dimensiones del texto
            Cairo.TextExtents extents;
            cr.text_extents(dimensions_text, out extents);
            
            // Dibujar el fondo negro semitransparente
            cr.set_source_rgba(0, 0, 0, 0.7);
            cr.rectangle(
                text_x - 5,
                text_y - extents.height - 5,
                extents.width + 10,
                extents.height * 2 + 10
            );
            cr.fill();
            
            // Dibujar el texto en blanco
            cr.set_source_rgba(1, 1, 1, 1);
            cr.move_to(text_x, text_y);
            cr.show_text(@"Ancho: $width px");
            cr.move_to(text_x, text_y + extents.height + 5);
            cr.show_text(@"Alto: $height px");
            
            // Actualizar últimas dimensiones
            last_width = width;
            last_height = height;
        }
        
        // Añadir el dibujo del color picker
        if (is_picking_color) {
            draw_color_picker(cr);
        }
        
        return false;
    }
    
    private void draw_resize_handle(Cairo.Context cr, double x, double y) {
        cr.rectangle(x - HANDLE_SIZE/2, y - HANDLE_SIZE/2, HANDLE_SIZE, HANDLE_SIZE);
        cr.fill();
    }
    
    private int get_resize_handle(double x, double y) {
        // Verificar cada esquina
        if (is_near_point(x, y, start_x, start_y)) return 1;
        if (is_near_point(x, y, current_x, start_y)) return 2;
        if (is_near_point(x, y, current_x, current_y)) return 3;
        if (is_near_point(x, y, start_x, current_y)) return 4;
        return 0;
    }
    
    private bool is_near_point(double x, double y, double px, double py) {
        return (Math.fabs(x - px) <= HANDLE_SIZE/2 && Math.fabs(y - py) <= HANDLE_SIZE/2);
    }
    
    private bool is_inside_rectangle(double x, double y) {
        double min_x = double.min(start_x, current_x);
        double max_x = double.max(start_x, current_x);
        double min_y = double.min(start_y, current_y);
        double max_y = double.max(start_y, current_y);
        
        return (x >= min_x && x <= max_x && y >= min_y && y <= max_y);
    }
    
    private bool on_button_press(Gdk.EventButton event) {
        if (event.button == 1) {
            resize_handle = get_resize_handle(event.x, event.y);
            
            if (resize_handle > 0) {
                is_resizing = true;
            } else if (is_inside_rectangle(event.x, event.y)) {
                is_moving = true;
                drag_offset_x = event.x - start_x;
                drag_offset_y = event.y - start_y;
            } else {
                is_measuring = true;
                start_x = event.x;
                start_y = event.y;
                current_x = event.x;
                current_y = event.y;
            }
            this.queue_draw();
        }
        return true;
    }
    
    private bool on_button_release(Gdk.EventButton event) {
        if (event.button == 1) {
            is_measuring = false;
            is_moving = false;
            is_resizing = false;
            this.queue_draw();
        }
        return true;
    }
    
    private bool on_motion(Gdk.EventMotion event) {
        if (is_measuring) {
            current_x = event.x;
            current_y = event.y;
        } else if (is_moving) {
            double dx = event.x - drag_offset_x;
            double dy = event.y - drag_offset_y;
            double width = current_x - start_x;
            double height = current_y - start_y;
            
            start_x = dx;
            start_y = dy;
            current_x = dx + width;
            current_y = dy + height;
        } else if (is_resizing) {
            switch (resize_handle) {
                case 1: // Esquina superior izquierda
                    start_x = event.x;
                    start_y = event.y;
                    break;
                case 2: // Esquina superior derecha
                    current_x = event.x;
                    start_y = event.y;
                    break;
                case 3: // Esquina inferior derecha
                    current_x = event.x;
                    current_y = event.y;
                    break;
                case 4: // Esquina inferior izquierda
                    start_x = event.x;
                    current_y = event.y;
                    break;
            }
        }
        
        if (is_measuring || is_moving || is_resizing) {
            this.queue_draw();
        }
        return true;
    }
    
    private void draw_color_picker(Cairo.Context cr) {
        try {
            // Obtener la posición actual del mouse
            int x, y;
            var display = Gdk.Display.get_default();
            var seat = display.get_default_seat();
            var device = seat.get_pointer();
            var window = this.get_window();
            window.get_device_position(device, out x, out y, null);
            
            // Capturar el área alrededor del cursor
            var root_window = screen.get_root_window();
            int capture_size = MAGNIFIER_SIZE / MAGNIFIER_ZOOM;
            int offset = capture_size / 2;
            
            var pixbuf = Gdk.pixbuf_get_from_window(
                root_window,
                x - offset,
                y - offset,
                capture_size,
                capture_size
            );
            
            // Crear una superficie circular para la lupa
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, MAGNIFIER_SIZE, MAGNIFIER_SIZE);
            var magnifier_cr = new Cairo.Context(surface);
            
            // Crear el recorte circular
            magnifier_cr.arc(MAGNIFIER_SIZE/2, MAGNIFIER_SIZE/2, MAGNIFIER_SIZE/2, 0, 2 * Math.PI);
            magnifier_cr.clip();
            
            // Dibujar el fondo negro semitransparente
            magnifier_cr.set_source_rgba(0, 0, 0, 0.7);
            magnifier_cr.paint();
            
            // Escalar y dibujar la imagen capturada
            magnifier_cr.scale(MAGNIFIER_ZOOM, MAGNIFIER_ZOOM);
            Gdk.cairo_set_source_pixbuf(magnifier_cr, pixbuf, 0, 0);
            magnifier_cr.paint();
            
            // Dibujar la cruz central
            magnifier_cr.identity_matrix(); // Resetear la transformación
            magnifier_cr.set_source_rgba(1, 1, 1, 0.8);
            magnifier_cr.set_line_width(1);
            magnifier_cr.move_to(MAGNIFIER_SIZE/2 - 10, MAGNIFIER_SIZE/2);
            magnifier_cr.line_to(MAGNIFIER_SIZE/2 + 10, MAGNIFIER_SIZE/2);
            magnifier_cr.move_to(MAGNIFIER_SIZE/2, MAGNIFIER_SIZE/2 - 10);
            magnifier_cr.line_to(MAGNIFIER_SIZE/2, MAGNIFIER_SIZE/2 + 10);
            magnifier_cr.stroke();
            
            // Dibujar la lupa en la pantalla
            cr.set_source_surface(surface, x - MAGNIFIER_SIZE/2, y - MAGNIFIER_SIZE - 40);
            cr.paint();
            
            // Obtener el color del píxel central
            unowned uint8[] pixels = pixbuf.get_pixels();
            int channels = pixbuf.get_n_channels();
            int rowstride = pixbuf.get_rowstride();
            int center = (offset * rowstride) + (offset * channels);
            
            uint8 r = pixels[center];
            uint8 g = pixels[center + 1];
            uint8 b = pixels[center + 2];
            
            // Actualizar los valores de color actuales
            current_hex_color = "#%02X%02X%02X".printf(r, g, b);
            current_rgb_color = "RGB(%d, %d, %d)".printf(r, g, b);
            
            // Mostrar los valores de color
            cr.set_source_rgba(0, 0, 0, 0.7);
            cr.rectangle(x - 70, y + 10, 140, 50);
            cr.fill();
            
            cr.set_source_rgba(1, 1, 1, 1);
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size(12);
            cr.move_to(x - 60, y + 30);
            cr.show_text(current_hex_color);
            cr.move_to(x - 60, y + 50);
            cr.show_text(current_rgb_color);
            
        } catch (Error e) {
            stderr.printf("Error en el color picker: %s\n", e.message);
        }
    }
    
    private void save_color(string hex_color, string rgb_color) {
        try {
            var file = File.new_for_path(color_history_file);
            
            // Leer colores existentes
            string[] colors = {};
            if (file.query_exists()) {
                string content;
                FileUtils.get_contents(color_history_file, out content);
                colors = content.split("\n");
            }
            
            // Añadir nuevo color al inicio
            var now = new DateTime.now_local();
            string new_color = "%s | %s | %s".printf(
                hex_color,
                rgb_color,
                now.format("%Y-%m-%d %H:%M:%S")
            );
            
            // Crear nueva lista de colores
            string[] new_colors = { new_color };
            foreach (string color in colors) {
                if (color.strip() != "" && new_colors.length < MAX_COLORS) {
                    new_colors += color;
                }
            }
            
            // Guardar al archivo
            string content = string.joinv("\n", new_colors);
            FileUtils.set_contents(color_history_file, content);
            
        } catch (Error e) {
            stderr.printf("Error al guardar el color: %s\n", e.message);
        }
    }
    
    private void show_copy_notification(string message) {
        var notification = new Gtk.Window(Gtk.WindowType.POPUP);
        notification.set_default_size(200, 40);
        
        var label = new Gtk.Label(message);
        label.margin = 10;
        notification.add(label);
        
        // Posicionar la notificación
        var workarea = screen.get_monitor_workarea(screen.get_primary_monitor());
        notification.move(
            workarea.x + (workarea.width - 200) / 2,
            workarea.y + (workarea.height - 40) / 2
        );
        
        notification.show_all();
        
        // Cerrar la notificación después de 1 segundo
        GLib.Timeout.add(1000, () => {
            notification.destroy();
            return false;
        });
    }
    
    public static int main(string[] args) {
        Gtk.init(ref args);
        
        var window = new MeasureTool();
        window.destroy.connect(Gtk.main_quit);
        window.show_all();
        
        Gtk.main();
        return 0;
    }
}
