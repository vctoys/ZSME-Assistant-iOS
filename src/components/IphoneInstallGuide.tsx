import { useState } from 'react';
import { CloudUpload, ExternalLink, ShieldCheck, Smartphone, Usb, Wifi } from 'lucide-react';

type InstallMethod = 'sidestore' | 'sideloadly' | 'linux' | 'testflight';

export function IphoneInstallGuide() {
  const [method, setMethod] = useState<InstallMethod>('sidestore');

  return (
    <div className="space-y-8">
      <div className="border-b border-slate-200 dark:border-slate-800 pb-6">
        <p className="text-xs font-medium text-[#0F4C81] dark:text-sky-400">
          Windows · Linux · Bez Jailbreaka · iOS 16 – iOS 18+
        </p>
        <h1 className="mt-2 text-2xl sm:text-3xl font-bold tracking-tight text-slate-900 dark:text-slate-100 text-balance">
          Instalacja natywnej aplikacji na iPhone z Windowsa lub Linuksa
        </h1>
        <p className="mt-2 max-w-3xl text-sm sm:text-base text-slate-600 dark:text-slate-400 leading-relaxed">
          Nie musisz jailbreakować iPhone&apos;a ani mieć Maca. Możesz użyć darmowego sideloadingu (SideStore / Sideloadly)
          albo automatycznie wysłać aplikację do <strong className="font-semibold text-slate-900 dark:text-slate-100">Apple TestFlight</strong> przez GitHub Actions (wymaga konta Apple Developer).
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2 p-1.5 bg-slate-100 dark:bg-slate-900 rounded-xl w-fit border border-slate-200 dark:border-slate-800">
        <button
          onClick={() => setMethod('sidestore')}
          className={`px-4 py-2 text-xs font-medium rounded-lg transition-colors whitespace-nowrap ${
            method === 'sidestore'
              ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          SideStore (Bez kabla po 1. razie — Darmowe)
        </button>
        <button
          onClick={() => setMethod('sideloadly')}
          className={`px-4 py-2 text-xs font-medium rounded-lg transition-colors whitespace-nowrap ${
            method === 'sideloadly'
              ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          Sideloadly (1 kliknięcie na Windows)
        </button>
        <button
          onClick={() => setMethod('linux')}
          className={`px-4 py-2 text-xs font-medium rounded-lg transition-colors whitespace-nowrap ${
            method === 'linux'
              ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          Linux (AltServer-Linux / SideStore)
        </button>
        <button
          onClick={() => setMethod('testflight')}
          className={`px-4 py-2 text-xs font-medium rounded-lg transition-colors whitespace-nowrap ${
            method === 'testflight'
              ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
              : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200'
          }`}
        >
          TestFlight (GitHub Actions + Apple Dev)
        </button>
      </div>

      {method === 'sidestore' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-5">
            <div className="flex items-center justify-between gap-4">
              <div className="flex items-center gap-2.5">
                <Wifi className="w-5 h-5 text-[#0F4C81] dark:text-sky-400" />
                <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
                  SideStore — instalujesz raz, później aktualizujesz i odświeżasz bezpośrednio na iPhone
                </h2>
              </div>
            </div>
            <ol className="space-y-4 text-sm text-slate-700 dark:text-slate-300">
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">01.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Jednorazowa instalacja SideStore z Windowsa lub Linuksa:</strong>{' '}
                  Pobierz instalator ze strony <a href="https://sidestore.io/" target="_blank" rel="noreferrer" className="text-[#0F4C81] dark:text-sky-400 underline">sidestore.io</a> i wgraj SideStore na iPhone&apos;a używając zwykłego, darmowego Apple ID. Od tego momentu komputer nie jest już potrzebny.
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">02.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Pobierz plik .ipa lub dodaj źródło w Safari na iPhonie:</strong>{' '}
                  Otwórz swoje wydanie na GitHub Releases bezpośrednio na iPhonie i pobierz <code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">ZSMEAssistant.ipa</code> (albo dodaj URL pliku <code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">altstore-source.json</code> w zakładce Sources w SideStore).
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">03.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Zainstaluj jednym stuknięciem:</strong>{' '}
                  Włącz na chwilę lokalny tunel WireGuard/StosVPN (wymagany przez SideStore), otwórz SideStore → <strong>My Apps → +</strong> i wybierz <code className="text-xs">ZSMEAssistant.ipa</code>.
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">04.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Automatyczne odświeżanie co 7 dni:</strong>{' '}
                  Darmowe certyfikaty Apple wygasają po 7 dniach, ale SideStore odnawia je automatycznie w tle przez Wi-Fi na samym iPhonie — nigdy nie stracisz dostępu do planu lekcji.
                </div>
              </li>
            </ol>
          </div>

          <IphoneTrustChecklist />
        </div>
      )}

      {method === 'sideloadly' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-5">
            <div className="flex items-center gap-2.5">
              <Usb className="w-5 h-5 text-[#0F4C81] dark:text-sky-400" />
              <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
                Sideloadly — najszybsze wgrywanie pliku .ipa z systemu Windows
              </h2>
            </div>
            <ol className="space-y-4 text-sm text-slate-700 dark:text-slate-300">
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">01.</span>
                <div>
                  Pobierz i zainstaluj darmowy program{' '}
                  <a href="https://sideloadly.io/" target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-[#0F4C81] dark:text-sky-400 underline">
                    Sideloadly <ExternalLink className="w-3 h-3" />
                  </a>{' '}
                  oraz Apple Devices / iTunes (ze strony Apple, nie ze sklepu Microsoft Store, jeśli używasz starszej wersji).
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">02.</span>
                <div>
                  Podłącz iPhone&apos;a kablem USB do komputera z Windowsem i zatwierdź komunikat <strong>Zaufaj temu komputerowi</strong> na ekranie telefonu.
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">03.</span>
                <div>
                  Przeciągnij plik <code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">ZSMEAssistant.ipa</code> (pobrany z GitHub Releases) na okno Sideloadly, wpisz swój Apple ID i kliknij <strong>Start</strong>.
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">04.</span>
                <div>
                  Sideloadly wspiera także automatyczne odświeżanie po Wi-Fi (<strong>Automatic Wi-Fi Refresh</strong>), gdy telefon i komputer z Windows są w tej samej sieci domowej.
                </div>
              </li>
            </ol>
          </div>

          <IphoneTrustChecklist />
        </div>
      )}

      {method === 'linux' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-5">
            <div className="flex items-center gap-2.5">
              <Smartphone className="w-5 h-5 text-[#0F4C81] dark:text-sky-400" />
              <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
                Linux — instalacja SideStore przez AltServer-Linux / Sideloader
              </h2>
            </div>
            <ol className="space-y-4 text-sm text-slate-700 dark:text-slate-300">
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">01.</span>
                <div>
                  Upewnij się, że w systemie działa usługa <code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">usbmuxd</code> (<code className="text-xs">sudo apt install usbmuxd libimobiledevice6</code> na Ubuntu/Debian).
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">02.</span>
                <div>
                  Użyj narzędzia{' '}
                  <a href="https://github.com/Dadoum/Sideloader" target="_blank" rel="noreferrer" className="text-[#0F4C81] dark:text-sky-400 underline">
                    Sideloader (Linux GUI/CLI)
                  </a>{' '}
                  lub <code className="text-xs">AltServer-Linux</code>, aby wgrać plik <code className="text-xs">ZSMEAssistant.ipa</code> bezpośrednio po USB albo zainstalować raz SideStore.
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">03.</span>
                <div>
                  Po pierwszym wgraniu możesz odświeżać aplikację bezpośrednio z iPhone&apos;a (w SideStore) bez podpinania do Linuksa.
                </div>
              </li>
            </ol>
          </div>

          <IphoneTrustChecklist />
        </div>
      )}

      {method === 'testflight' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-5">
            <div className="flex items-center gap-2.5">
              <CloudUpload className="w-5 h-5 text-[#0F4C81] dark:text-sky-400" />
              <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
                TestFlight — automatyczna wysyłka z GitHub Actions (bez Maca)
              </h2>
            </div>
            <p className="text-xs sm:text-sm text-amber-800 dark:text-amber-300 bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800/60 rounded-lg px-3.5 py-2.5">
              Wymaganie Apple: publikacja w <strong>TestFlight</strong> wymaga płatnego konta <strong>Apple Developer Program ($99/rok)</strong>.
              Maca nie potrzebujesz — certyfikat wygenerujesz w OpenSSL na Windows/Linux, a kompilację i wysyłkę wykona workflow{' '}
              <code className="text-xs">.github/workflows/deploy-testflight.yml</code>.
            </p>
            <ol className="space-y-4 text-sm text-slate-700 dark:text-slate-300">
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">01.</span>
                <div className="space-y-2 w-full">
                  <div>
                    <strong className="font-semibold text-slate-900 dark:text-slate-100">Wygeneruj certyfikat Apple Distribution (.p12) bez Maca:</strong>{' '}
                    W Git Bash (Windows) lub Terminalu (Linux) utwórz CSR, wgraj go na <code className="text-xs">developer.apple.com → Certificates → + → Apple Distribution</code>, pobierz <code className="text-xs">distribution.cer</code> i zamień na <code className="text-xs">distribution.p12</code>:
                  </div>
                  <pre className="p-3 rounded-lg bg-slate-950 text-slate-100 text-[11px] overflow-x-auto font-mono leading-relaxed">
{`openssl genrsa -out ios_dist.key 2048
openssl req -new -key ios_dist.key -out ios_dist.csr -subj "/CN=ZSME Assistant/C=PL"
# Pobierz distribution.cer z developer.apple.com, a następnie:
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -out distribution.p12 -inkey ios_dist.key -in distribution.pem -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`}
                  </pre>
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">02.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Profil, App ID i klucz App Store Connect API (.p8):</strong>{' '}
                  Zarejestruj swój App ID (np. <code className="text-xs">pl.twojanazwa.zsmeassistant</code>), wygeneruj profil <strong>Distribution → App Store Connect</strong> (<code className="text-xs">.mobileprovision</code>), utwórz aplikację w App Store Connect oraz klucz API w <code className="text-xs">Users and Access → Integrations</code> (<code className="text-xs">AuthKey_XXXX.p8</code>).
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">03.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Dodaj 6 sekretów w GitHub Actions:</strong>{' '}
                  W repozytorium otwórz <code className="text-xs">Settings → Secrets and variables → Actions</code> i zapisz:{' '}
                  <code className="text-xs">IOS_DIST_CERT_BASE64</code>, <code className="text-xs">IOS_DIST_CERT_PASSWORD</code>,{' '}
                  <code className="text-xs">IOS_PROVISIONING_PROFILE_BASE64</code>, <code className="text-xs">ASC_API_KEY_ID</code>,{' '}
                  <code className="text-xs">ASC_API_ISSUER_ID</code> oraz <code className="text-xs">ASC_API_KEY_P8_BASE64</code>.
                </div>
              </li>
              <li className="flex gap-3">
                <span className="font-mono font-semibold text-[#0F4C81] dark:text-sky-400 tabular-nums">04.</span>
                <div>
                  <strong className="font-semibold text-slate-900 dark:text-slate-100">Uruchom wysyłkę jednym kliknięciem:</strong>{' '}
                  Na GitHubie wejdź w <strong>Actions → Publikacja na TestFlight (App Store Connect) → Run workflow</strong>. Po ok. 3 minutach build trafi do TestFlight gotowy do instalacji linkiem lub zaproszeniem (ważność 90 dni bez odświeżania co tydzień).
                </div>
              </li>
            </ol>
          </div>

          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-4">
            <div className="flex items-center gap-2">
              <ShieldCheck className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
              <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">
                Co robi workflow TestFlight?
              </h3>
            </div>
            <ul className="space-y-3 text-xs sm:text-sm text-slate-600 dark:text-slate-400">
              <li>
                <strong className="text-slate-900 dark:text-slate-100">1. Automatyczne wykrywanie Bundle ID:</strong>{' '}
                Odczytuje Twój <code className="text-xs">Team ID</code> i <code className="text-xs">Bundle ID</code> prosto z pliku <code className="text-xs">.mobileprovision</code>.
              </li>
              <li>
                <strong className="text-slate-900 dark:text-slate-100">2. Brak pytań o szyfrowanie:</strong>{' '}
                W <code className="text-xs">Info.plist</code> ustawiono <code className="text-xs">ITSAppUsesNonExemptEncryption = false</code>, więc buildy od razu trafiają do testerów.
              </li>
              <li>
                <strong className="text-slate-900 dark:text-slate-100">3. Unikalny numer buildu:</strong>{' '}
                Każde uruchomienie automatycznie podbija <code className="text-xs">CFBundleVersion</code> do numeru uruchomienia GitHub Actions.
              </li>
            </ul>
          </div>
        </div>
      )}
    </div>
  );
}

function IphoneTrustChecklist() {
  return (
    <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-4">
      <div className="flex items-center gap-2">
        <ShieldCheck className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
        <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">
          Jednorazowe ustawienia na iPhone (iOS 16+)
        </h3>
      </div>
      <ul className="space-y-3 text-xs sm:text-sm text-slate-600 dark:text-slate-400">
        <li>
          <strong className="text-slate-900 dark:text-slate-100">1. Zaufaj profilowi dewelopera:</strong>{' '}
          Ustawienia → Ogólne → VPN i zarządzanie urządzeniem → kliknij swój Apple ID → <em>Zaufaj</em>.
        </li>
        <li>
          <strong className="text-slate-900 dark:text-slate-100">2. Włącz Tryb dewelopera:</strong>{' '}
          Ustawienia → Prywatność i ochrona → Tryb dewelopera (na samym dole) → Włącz i uruchom ponownie iPhone&apos;a.
        </li>
        <li>
          <strong className="text-slate-900 dark:text-slate-100">3. Uprawnienia natywne:</strong>{' '}
          Przy pierwszym uruchomieniu zezwól aplikacji na Bluetooth (Komunikator BLE Mesh), Kalendarz (eksport EventKit) i Powiadomienia (alerty o zastępstwach).
        </li>
      </ul>
    </div>
  );
}
