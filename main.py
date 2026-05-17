import os
import threading
from time import sleep

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.clock import Clock

from jnius import autoclass, PythonJavaClass, java_method, cast
from deep_translator import GoogleTranslator
from langdetect import detect

# --- Native Android Classes ---
PythonActivity = autoclass('org.kivy.android.PythonActivity')
Context = autoclass('android.content.Context')
Settings = autoclass('android.provider.Settings')
Uri = autoclass('android.net.Uri')
Intent = autoclass('android.content.Intent')
WindowManager = autoclass('android.view.WindowManager')
LayoutParams = autoclass('android.view.WindowManager$LayoutParams')
Gravity = autoclass('android.view.Gravity')
PixelFormat = autoclass('android.graphics.PixelFormat')
Build = autoclass('android.os.Build$VERSION')

# View & Layouts
LinearLayout = autoclass('android.widget.LinearLayout')
AndroidButton = autoclass('android.widget.Button')
AndroidTextView = autoclass('android.widget.TextView')
Color = autoclass('android.graphics.Color')
View = autoclass('android.view.View')
MotionEvent = autoclass('android.view.MotionEvent')

# Media Projection & Image classes
MediaProjectionManager = autoclass('android.media.projection.MediaProjectionManager')
ImageReader = autoclass('android.media.ImageReader')
ImageFormat = autoclass('android.graphics.ImageFormat')
DisplayMetrics = autoclass('android.util.DisplayMetrics')
Bitmap = autoclass('android.graphics.Bitmap')

# ML Kit OCR
TextRecognition = autoclass('com.google.mlkit.vision.text.TextRecognition')
TextRecognizerOptions = autoclass('com.google.mlkit.vision.text.latin.TextRecognizerOptions')
InputImage = autoclass('com.google.mlkit.vision.common.InputImage')

# --- Helper to run code on Android UI Thread ---
class UIRunnable(PythonJavaClass):
    __javainterfaces__ = ['java/lang/Runnable']
    def __init__(self, func):
        super(UIRunnable, self).__init__()
        self.func = func
    @java_method('()V')
    def run(self):
        self.func()

def run_on_ui_thread(func):
    PythonActivity.mActivity.runOnUiThread(UIRunnable(func))

# --- ML Kit Task Listeners ---
class OnSuccessListener(PythonJavaClass):
    __javainterfaces__ = ['com/google/android/gms/tasks/OnSuccessListener']
    def __init__(self, callback):
        super(OnSuccessListener, self).__init__()
        self.callback = callback
    @java_method('(Ljava/lang/Object;)V')
    def onSuccess(self, result):
        self.callback(result.getText())

class OnFailureListener(PythonJavaClass):
    __javainterfaces__ = ['com/google/android/gms/tasks/OnFailureListener']
    def __init__(self, callback):
        super(OnFailureListener, self).__init__()
        self.callback = callback
    @java_method('(Ljava/lang/Exception;)V')
    def onFailure(self, exception):
        self.callback(None)

# --- Bubble Touch Listener ---
class BubbleTouchListener(PythonJavaClass):
    __javainterfaces__ = ['android/view/View$OnTouchListener']
    def __init__(self, layout, params, window_manager, on_click_callback):
        super(BubbleTouchListener, self).__init__()
        self.layout = layout
        self.params = params
        self.window_manager = window_manager
        self.on_click_callback = on_click_callback
        self.initialX = 0
        self.initialY = 0
        self.initialTouchX = 0.0
        self.initialTouchY = 0.0
        self.is_drag = False

    @java_method('(Landroid/view/View;Landroid/view/MotionEvent;)Z')
    def onTouch(self, view, event):
        action = event.getAction()
        if action == MotionEvent.ACTION_DOWN:
            self.initialX = self.params.x
            self.initialY = self.params.y
            self.initialTouchX = event.getRawX()
            self.initialTouchY = event.getRawY()
            self.is_drag = False
            return True
        elif action == MotionEvent.ACTION_UP:
            if not self.is_drag:
                # It's a click! Trigger translation.
                self.on_click_callback()
            return True
        elif action == MotionEvent.ACTION_MOVE:
            dx = event.getRawX() - self.initialTouchX
            dy = event.getRawY() - self.initialTouchY
            if abs(dx) > 10 or abs(dy) > 10:
                self.is_drag = True
                self.params.x = self.initialX + int(dx)
                self.params.y = self.initialY + int(dy)
                self.window_manager.updateViewLayout(self.layout, self.params)
            return True
        return False

# --- Main App ---
class BubbleTranslatorApp(App):
    def build(self):
        self.activity = PythonActivity.mActivity
        self.window_manager = self.activity.getSystemService(Context.WINDOW_SERVICE)
        self.media_projection_manager = self.activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
        
        self.media_projection = None
        self.virtual_display = None
        self.image_reader = None
        self.bubble_layout = None
        self.text_view = None

        layout = BoxLayout(orientation='vertical', padding=50, spacing=20)
        layout.add_widget(Label(text="Bubble Translator", font_size=32))
        
        btn_start = Button(text="1. Grant Permissions & Start", size_hint=(1, 0.2))
        btn_start.bind(on_press=self.setup_and_start)
        layout.add_widget(btn_start)

        # Bind to Kivy's activity result to catch the MediaProjection consent
        from android import activity
        activity.bind(on_activity_result=self.on_activity_result)
        
        return layout

    def setup_and_start(self, instance):
        # 1. Check Overlay Permission
        if not Settings.canDrawOverlays(self.activity):
            intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + self.activity.getPackageName()))
            self.activity.startActivity(intent)
            return
            
        # 2. Start Dummy Foreground Service (required for MediaProjection on Android 10+)
        from android import AndroidService
        service = AndroidService('BubbleService', 'running')
        service.start('Foreground')

        # 3. Request Media Projection
        intent = self.media_projection_manager.createScreenCaptureIntent()
        self.activity.startActivityForResult(intent, 1001)

    def on_activity_result(self, requestCode, resultCode, intent):
        if requestCode == 1001 and resultCode == -1: # RESULT_OK
            # Initialize MediaProjection
            self.media_projection = self.media_projection_manager.getMediaProjection(resultCode, intent)
            self.setup_image_reader()
            self.create_floating_bubble()
            
            # Send app to background so the user can browse
            self.activity.moveTaskToBack(True)

    def setup_image_reader(self):
        metrics = DisplayMetrics()
        self.window_manager.getDefaultDisplay().getMetrics(metrics)
        self.screen_w = metrics.widthPixels
        self.screen_h = metrics.heightPixels
        self.screen_density = metrics.densityDpi

        # Create ImageReader
        self.image_reader = ImageReader.newInstance(self.screen_w, self.screen_h, PixelFormat.RGBA_8888, 2)
        
        # Attach to VirtualDisplay
        self.virtual_display = self.media_projection.createVirtualDisplay(
            "ScreenCapture",
            self.screen_w, self.screen_h, self.screen_density,
            16, # DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR
            self.image_reader.getSurface(), None, None
        )

    def create_floating_bubble(self):
        def _ui_setup():
            # Layout Params for Floating Window
            type_overlay = LayoutParams.TYPE_APPLICATION_OVERLAY if Build.SDK_INT >= 26 else 2002 # TYPE_PHONE
            self.bubble_params = LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT,
                type_overlay,
                LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )
            self.bubble_params.gravity = Gravity.TOP | Gravity.LEFT
            self.bubble_params.x = 50
            self.bubble_params.y = 50

            self.bubble_layout = LinearLayout(self.activity)
            self.bubble_layout.setOrientation(LinearLayout.VERTICAL)

            # Translation Bubble Icon
            btn = AndroidButton(self.activity)
            btn.setText("🌍")
            btn.setTextSize(30.0)
            btn.setBackgroundColor(Color.parseColor("#CC000000")) # Semi-transparent black

            # Translation Result Text
            self.text_view = AndroidTextView(self.activity)
            self.text_view.setText(" Ready")
            self.text_view.setTextColor(Color.WHITE)
            self.text_view.setBackgroundColor(Color.parseColor("#99000000"))
            self.text_view.setTextSize(16.0)

            self.bubble_layout.addView(btn)
            self.bubble_layout.addView(self.text_view)

            # Attach touch listener for dragging and clicking
            self.listener = BubbleTouchListener(self.bubble_layout, self.bubble_params, self.window_manager, self.on_bubble_click)
            self.bubble_layout.setOnTouchListener(self.listener)

            self.window_manager.addView(self.bubble_layout, self.bubble_params)

        run_on_ui_thread(_ui_setup)

    def on_bubble_click(self):
        # 1. Hide bubble so it isn't included in the screenshot
        def _hide():
            self.text_view.setText(" Capturing...")
            self.bubble_layout.setVisibility(View.INVISIBLE)
        run_on_ui_thread(_hide)

        # 2. Wait 150ms for UI to update, then capture
        Clock.schedule_once(lambda dt: self.capture_and_process(), 0.15)

    def capture_and_process(self):
        # Read the latest image from the Surface
        image = self.image_reader.acquireLatestImage()
        if not image:
            self.show_result("Error: No screen capture available.")
            return

        planes = image.getPlanes()
        buffer = planes[0].getBuffer()
        pixelStride = planes[0].getPixelStride()
        rowStride = planes[0].getRowStride()
        rowPadding = rowStride - pixelStride * self.screen_w

        # Convert buffer to Android Bitmap
        bitmap = Bitmap.createBitmap(self.screen_w + int(rowPadding / pixelStride), self.screen_h, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(buffer)
        
        # Crop the padding out
        cropped_bitmap = Bitmap.createBitmap(bitmap, 0, 0, self.screen_w, self.screen_h)
        image.close()

        # Execute OCR and Translation in a background thread
        threading.Thread(target=self.run_ocr_and_translate, args=(cropped_bitmap,)).start()

    def run_ocr_and_translate(self, bitmap):
        # Setup ML Kit OCR
        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        input_image = InputImage.fromBitmap(bitmap, 0)
        task = recognizer.process(input_image)

        def _on_success(text):
            if not text or len(text.strip()) == 0:
                self.show_result("No text found.")
                return
            
            # Run translation in Python
            try:
                # Detect language (optional, deep_translator auto-detects, but useful for logs)
                lang = detect(text)
                # Translate to English (target='en')
                translated = GoogleTranslator(source='auto', target='en').translate(text)
                self.show_result(f" [{lang}]\n{translated}")
            except Exception as e:
                self.show_result(f"Translation Error")

        def _on_failure():
            self.show_result("OCR Failed.")

        # Bind listeners
        task.addOnSuccessListener(OnSuccessListener(_on_success))
        task.addOnFailureListener(OnFailureListener(_on_failure))

    def show_result(self, text):
        def _update_ui():
            self.text_view.setText(text)
            self.bubble_layout.setVisibility(View.VISIBLE)
        run_on_ui_thread(_update_ui)

if __name__ == '__main__':
    BubbleTranslatorApp().run()
