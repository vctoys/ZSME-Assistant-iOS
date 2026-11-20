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

## 3. Publikacja w Apple TestFlight (bez Maca, przez GitHub Actions)

Dodany został osobny workflow `.github/workflows/deploy-testflight.yml`, który automatycznie podpisuje aplikację i wysyła ją do **TestFlight** (wymaga płatnego konta **Apple Developer Program — $99/rok**, ponieważ Apple nie pozwala na TestFlight z darmowego Apple ID).

1. **Wygeneruj certyfikat `Apple Distribution` (.p12) bez Maca** (w Git Bash na Windowsie lub na Linuksie):
   ```bash
   openssl genrsa -out ios_dist.key 2048
   openssl req -new -key ios_dist.key -out ios_dist.csr -subj "/CN=ZSME Assistant/C=PL"
   ```
   Wgraj `ios_dist.csr` w [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) (typ **Apple Distribution**), pobierz `distribution.cer`, a potem spakuj do `.p12`:
   ```bash
   openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
   openssl pkcs12 -export -out distribution.p12 -inkey ios_dist.key -in distribution.pem -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
   ```
2. **Utwórz App ID, rekord aplikacji i profil `.mobileprovision`**:
   - W **Identifiers** zarejestruj App ID (np. `pl.twojanazwa.zsmeassistant`).
   - W **Profiles** utwórz profil typu **Distribution → App Store Connect** dla tego App ID i pobierz plik `.mobileprovision`.
   - W [App Store Connect](https://appstoreconnect.apple.com/) utwórz nową aplikację (**My Apps → +**) z tym samym Bundle ID oraz wygeneruj klucz API (**Users and Access → Integrations → App Store Connect API**, rola **App Manager** / **Admin**) i pobierz plik `AuthKey_XXXX.p8`.
3. **Dodaj 6 sekretów w repozytorium GitHub** (`Settings → Secrets and variables → Actions`):
   - `IOS_DIST_CERT_BASE64` — zawartość `distribution.p12` zakodowana w Base64 (`base64 -w0 distribution.p12`)
   - `IOS_DIST_CERT_PASSWORD` — hasło nadane plikowi `distribution.p12`
   - `IOS_PROVISIONING_PROFILE_BASE64` — zawartość `.mobileprovision` w Base64 (`base64 -w0 profil.mobileprovision`)
   - `ASC_API_KEY_ID` — ID klucza API z App Store Connect
   - `ASC_API_ISSUER_ID` — Issuer ID z App Store Connect
   - `ASC_API_KEY_P8_BASE64` — zawartość `AuthKey_XXXX.p8` w Base64 (`base64 -w0 AuthKey_XXXX.p8`)
4. **Uruchom wysyłkę**: W repozytorium GitHub otwórz **Actions → Publikacja na TestFlight (App Store Connect) → Run workflow** (lub wypchnij tag `testflight-1.0.0`). Po ~3 minutach build pojawi się w **TestFlight** gotowy do instalacji linkiem lub zaproszeniem!

