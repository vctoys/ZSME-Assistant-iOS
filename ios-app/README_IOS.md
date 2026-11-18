# ZSME Assistant — Natywna aplikacja iOS (bez Maca, bez Jailbreaka)

Pełna natywna aplikacja napisana w **Swift + SwiftUI** (iOS 16.0+), przeniesiona z Androida (`dniesobski/ZSME-Assistant`).
Nie jest to PWA ani nakładka WebView — to pełnoprawna natywna aplikacja wykorzystująca `URLSession`, `SwiftSoup`, `CoreBluetooth` (BLE Mesh), `EventKit` (Kalendarz Apple), `UserNotifications` i `BGTaskScheduler`.

## 1. Darmowa kompilacja w chmurze (bez Maca)

1. Utwórz darmowe, **publiczne** repozytorium na [GitHub](https://github.com/new) (publiczne repozytoria mają **nielimitowane darmowe minuty** na serwerach macOS w GitHub Actions).
2. Wypchnij zawartość tego folderu (`ios-app`) do repozytorium GitHub (pamiętając o ukrytym folderze `.github/workflows/build-ios-ipa.yml`).
3. GitHub Actions automatycznie uruchomi maszynę `macos-latest`, zainstaluje `XcodeGen`, pobierze `SwiftSoup` i skompiluje natywny plik **`ZSMEAssistant.ipa`**.
4. Po ok. 2–3 minutach wejdź w zakładkę **Releases** swojego repozytorium na GitHubie i pobierz gotowy plik `ZSMEAssistant.ipa`.

## 2. Bezproblemowa instalacja na iPhone (Windows / Linux, bez Jailbreaka)

### Opcja A: SideStore (Najwygodniejsza — po instalacji nie potrzebuje PC ani kabla!)
1. Zainstaluj raz **SideStore** na swoim iPhonie z poziomu Windows/Linux (instrukcja na [sidestore.io](https://sidestore.io/) — wymaga darmowego Apple ID, bez jailbreaka).
2. Pobierz plik `ZSMEAssistant.ipa` z GitHub Releases bezpośrednio w Safari na iPhonie.
3. Otwórz aplikację **SideStore → zakładka My Apps → ikona `+`** i wybierz pobrany plik `ZSMEAssistant.ipa` (lub dodaj wygenerowany plik `altstore-source.json` z Release jako źródło!).
4. SideStore podpisuje aplikację Twoim darmowym certyfikatem Apple ID i automatycznie odświeża go co 7 dni przez Wi-Fi / lokalny tunel VPN — bez podłączania telefonu do komputera.

### Opcja B: Sideloadly (Najszybsza na Windows z użyciem kabla lub Wi-Fi)
1. Pobierz darmowy program **Sideloadly** ([sideloadly.io](https://sideloadly.io/)) na Windows (lub macOS).
2. Podłącz iPhone'a do komputera i uruchom iTunes/Apple Devices (żeby wykryło telefon).
3. Przeciągnij plik `ZSMEAssistant.ipa` do okna Sideloadly, wpisz swój Apple ID i kliknij **Start**.
4. Na iPhonie wejdź w **Ustawienia → Ogólne → VPN i zarządzanie urządzeniem**, kliknij swój Apple ID i wybierz **Zaufaj**.
5. Od iOS 16 włącz jednorazowo **Tryb dewelopera** (**Ustawienia → Prywatność i ochrona → Tryb dewelopera**).

### Opcja C (Linux): AltServer-Linux / Sideloader (Plik `.ipa` przez libimobiledevice)
Na Linuksie możesz użyć **SideStore** (jednorazowa instalacja przez `altserver-linux` / `sideloader` z `usbmuxd`) i potem zarządzać wszystkim bezprzewodowo bezpośrednio na iPhonie.
