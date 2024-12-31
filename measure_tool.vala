public class MeasureTool : Gtk.Window {
    private bool is_measuring = false;
    private double start_x = 0;
    private double start_y = 0;
    private double current_x = 0;
    private double current_y = 0;
    private int last_width = 0;
    private int last_height = 0;
    
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
        
        // En lugar de fullscreen, maximizamos la ventana y la hacemos del tamaño del área de trabajo
        this.maximize();
        
        // Obtener las dimensiones del área de trabajo (excluyendo paneles)
        var screen = this.get_screen();
        var monitor = screen.get_primary_monitor();
        var workarea = screen.get_monitor_workarea(monitor);
        this.set_default_size(workarea.width, workarea.height);
        this.move(workarea.x, workarea.y);
        
        var drawing_area = new Gtk.DrawingArea();
        drawing_area.draw.connect(on_draw);
        
        // Configurar eventos del mouse para capturar todo
        var events = Gdk.EventMask.BUTTON_PRESS_MASK | 
                    Gdk.EventMask.BUTTON_RELEASE_MASK |
                    Gdk.EventMask.POINTER_MOTION_MASK |
                    Gdk.EventMask.POINTER_MOTION_HINT_MASK;
        drawing_area.add_events((int)events);
        
        drawing_area.button_press_event.connect(on_button_press);
        drawing_area.button_release_event.connect(on_button_release);
        drawing_area.motion_notify_event.connect(on_motion);
        
        this.add(drawing_area);
        this.set_default_size(800, 600);
        
        // Agregar eventos de teclado
        this.key_press_event.connect((event) => {
            if (event.keyval == Gdk.Key.Escape) {
                this.destroy();
                return true;
            }
            // Copiar dimensiones cuando se presiona Ctrl+C
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 && 
                (event.keyval == Gdk.Key.c || event.keyval == Gdk.Key.C)) {
                copy_dimensions();
                return true;
            }
            return false;
        });
    }
    
    private void copy_dimensions() {
        if (last_width == 0 && last_height == 0) {
            return; // No copiar si no hay medidas
        }
        
        string dimensions = @"Ancho: $(last_width)px\nAlto: $(last_height)px";
        var clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(dimensions, -1);
        
        // Mostrar una notificación de que se copió
        var notification = new Gtk.Window(Gtk.WindowType.POPUP);
        notification.set_default_size(200, 40);
        
        var label = new Gtk.Label("¡Dimensiones copiadas!");
        label.margin = 10;
        notification.add(label);
        
        // Posicionar la notificación en el centro de la pantalla
        var screen = this.get_screen();
        var monitor = screen.get_primary_monitor();
        var workarea = screen.get_monitor_workarea(monitor);
        
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
    
    private bool on_draw(Cairo.Context cr) {
        // Hacer el fondo transparente
        cr.set_source_rgba(0, 0, 0, 0);
        cr.set_operator(Cairo.Operator.SOURCE);
        cr.paint();
        cr.set_operator(Cairo.Operator.OVER);
        
        if (is_measuring) {
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
            
            // Dibujar punto de mira de origen
            cr.set_source_rgba(1, 0, 0, 0.8);
            draw_crosshair(cr, start_x, start_y, 10);
            
            // Dibujar punto de mira de destino
            cr.set_source_rgba(1, 0, 0, 0.8);
            draw_crosshair(cr, current_x, current_y, 10);
            
            // Mostrar medidas
            var width = (int)Math.fabs(current_x - start_x);
            var height = (int)Math.fabs(current_y - start_y);
            
            // Obtener dimensiones de la pantalla
            var screen = this.get_screen();
            var screen_width = screen.get_width();
            var screen_height = screen.get_height();
            
            // Tomar una captura del área medida
            var window = this.get_window();
            int x = (int)((start_x < current_x) ? start_x : current_x);
            int y = (int)((start_y < current_y) ? start_y : current_y);
            var pixbuf = Gdk.pixbuf_get_from_window(
                window,
                x,
                y,
                width,
                height
            );
            
            // Calcular el color promedio del área
            if (pixbuf != null) {
                unowned uint8[] pixels = pixbuf.get_pixels();
                int channels = pixbuf.get_n_channels();
                int rowstride = pixbuf.get_rowstride();
                
                double r_sum = 0, g_sum = 0, b_sum = 0;
                int pixel_count = width * height;
                
                // Tomar muestras del centro del área
                int sample_size = 10; // Número de píxeles a muestrear
                int center_x = width / 2;
                int center_y = height / 2;
                
                // Muestrear píxeles alrededor del centro
                for (int py = -sample_size; py < sample_size; py++) {
                    for (int px = -sample_size; px < sample_size; px++) {
                        int sample_x = center_x + px;
                        int sample_y = center_y + py;
                        
                        // Asegurarse de que estamos dentro de los límites
                        if (sample_x >= 0 && sample_x < width && sample_y >= 0 && sample_y < height) {
                            int position = sample_y * rowstride + sample_x * channels;
                            r_sum += pixels[position];
                            g_sum += pixels[position + 1];
                            b_sum += pixels[position + 2];
                            pixel_count++;
                        }
                    }
                }
                
                double avg_brightness = (r_sum + g_sum + b_sum) / (3 * pixel_count);
                stdout.printf("Brillo promedio: %f\n", avg_brightness);  // Para depuración
                
                // Ajustar el umbral para mejor detección
                if (avg_brightness > 200) {  // Aumentamos el umbral para superficies blancas
                    // Área clara - usar texto negro
                    cr.set_source_rgba(0, 0, 0, 1);
                    stdout.printf("Usando texto negro\n");
                } else {
                    // Área oscura - usar texto blanco
                    cr.set_source_rgba(1, 1, 1, 1);
                    stdout.printf("Usando texto blanco\n");
                }
            } else {
                // Si no se puede obtener el pixbuf, usar texto blanco por defecto
                cr.set_source_rgba(1, 1, 1, 1);
            }
            
            // Preparar el texto
            cr.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size(12);
            
            string dimensions_text = @"Ancho: $width px\nAlto: $height px";
            
            // Calcular posición del texto
            double text_x = current_x + 10;
            double text_y = current_y + 10;
            
            // Ajustar posición horizontal si está cerca del borde derecho
            if (text_x + 100 > screen_width) {
                text_x = current_x - 110;
            }
            
            // Ajustar posición vertical si está cerca del borde inferior
            if (text_y + 30 > screen_height) {
                text_y = current_y - 30;
            }
            
            // Obtener las dimensiones del texto
            Cairo.TextExtents extents;
            cr.text_extents(dimensions_text, out extents);
            
            // Dibujar el fondo negro semitransparente
            cr.set_source_rgba(0, 0, 0, 0.7);  // Negro con 70% de opacidad
            cr.rectangle(
                text_x - 5,                    // Un poco a la izquierda del texto
                text_y - extents.height - 5,   // Un poco arriba del texto
                extents.width + 10,            // Ancho del texto + padding
                extents.height * 2 + 10        // Alto del texto + padding
            );
            cr.fill();
            
            // Dibujar el texto en blanco
            cr.set_source_rgba(1, 1, 1, 1);    // Blanco sólido
            cr.move_to(text_x, text_y);
            cr.show_text(@"Ancho: $width px");
            cr.move_to(text_x, text_y + extents.height + 5);
            cr.show_text(@"Alto: $height px");
            
            // Actualizar las últimas dimensiones medidas
            last_width = width;
            last_height = height;
        }
        return false;
    }
    
    private void draw_crosshair(Cairo.Context cr, double x, double y, double size) {
        // Líneas horizontales
        cr.move_to(x - size, y);
        cr.line_to(x + size, y);
        
        // Líneas verticales
        cr.move_to(x, y - size);
        cr.line_to(x, y + size);
        
        // Círculo central
        cr.arc(x, y, size/4, 0, 2 * Math.PI);
        
        // Dibujar líneas adicionales en diagonal
        cr.move_to(x - size/2, y - size/2);
        cr.line_to(x + size/2, y + size/2);
        cr.move_to(x - size/2, y + size/2);
        cr.line_to(x + size/2, y - size/2);
        
        cr.stroke();
    }
    
    private bool on_button_press(Gdk.EventButton event) {
        if (event.button == 1) { // Solo botón izquierdo
            is_measuring = true;
            start_x = event.x;
            start_y = event.y;
            current_x = event.x;
            current_y = event.y;
            this.queue_draw();
        }
        return true;
    }
    
    private bool on_button_release(Gdk.EventButton event) {
        if (event.button == 1) { // Solo botón izquierdo
            is_measuring = false;
            this.queue_draw();
        }
        return true;
    }
    
    private bool on_motion(Gdk.EventMotion event) {
        if (is_measuring) {
            current_x = event.x;
            current_y = event.y;
            this.queue_draw();
        }
        return true;
    }
    
    public static int main(string[] args) {
        Gtk.init(ref args);
        
       
        // Establecer el ID de la aplicación
        GLib.Environment.set_application_name("Herramienta de Medición");
        Gtk.Window.set_default_icon_name("measure-tool");
        
        
        var window = new MeasureTool();
        window.destroy.connect(Gtk.main_quit);
        window.show_all();
        
        Gtk.main();
        return 0;
    }
}
