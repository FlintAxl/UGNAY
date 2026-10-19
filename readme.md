flutter devices
flutter run -d emulator-5554
flutter run -d 075112519G007854
.\.venv\Scripts\Activate.ps1

r   Hot reload
R   Hot restart

cd C:\Users\Axl\Desktop\ugnay\backend
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

cd C:\Users\Axl\Desktop\ugnay\face-service
uvicorn main:app --reload --host 0.0.0.0 --port 8001

