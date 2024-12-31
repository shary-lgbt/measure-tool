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
    private int resize_handle = 0; // 0: ninguno, 1-4: esquinas
    
    private const int HANDLE_SIZE = 10; // Tamaño del área para redimensionar
    
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
        drawing_area.motion_notify_event.connect(on_motion);
        
        this.add(drawing_area);
        
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
        
        GLib.Timeout.add(1000, () => {
            notification.destroy();
            return false;
        });
    }
    
    private bool on_draw(Cairo.Context cr) {
        cr.set_source_rgba(0, 0, 0, 0);
        cr.set_operator(Cairo.Operator.SOURCE);
        cr.paint();
        cr.set_operator(Cairo.Operator.OVER);
        
        // Si hay un rectángulo (cuando las dimensiones no son 0)
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
                // Si el clic es dentro del rectángulo, iniciamos el movimiento
                is_moving = true;
                // Guardamos el offset del punto de clic relativo a la esquina superior izquierda
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
            // Calculamos la nueva posición manteniendo el tamaño del rectángulo
            double width = current_x - start_x;
            double height = current_y - start_y;
            
            // Actualizamos la posición basada en el punto de arrastre
            start_x = event.x - drag_offset_x;
            start_y = event.y - drag_offset_y;
            current_x = start_x + width;
            current_y = start_y + height;
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
    
    public static int main(string[] args) {
        Gtk.init(ref args);
        
        GLib.Environment.set_application_name("Herramienta de Medición");
        Gtk.Window.set_default_icon_name("measure-tool");
        
        var window = new MeasureTool();
        window.destroy.connect(Gtk.main_quit);
        window.show_all();
        
        Gtk.main();
        return 0;
    }
}
