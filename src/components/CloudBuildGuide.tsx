import { useState } from 'react';
import { Check, Copy, Download, ExternalLink, Terminal } from 'lucide-react';

interface CloudBuildGuideProps {
  onDownloadZip: () => void;
}

export function CloudBuildGuide({ onDownloadZip }: CloudBuildGuideProps) {
  const [githubUser, setGithubUser] = useState('twoj-login');
  const [repoName, setRepoName] = useState('ZSME-Assistant-iOS');
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const cleanUser = githubUser.trim() || 'twoj-login';
  const cleanRepo = repoName.trim() || 'ZSME-Assistant-iOS';
  const releasesUrl = `https://github.com/${cleanUser}/${cleanRepo}/releases/latest`;
  const sideStoreSourceUrl = `https://github.com/${cleanUser}/${cleanRepo}/releases/latest/download/altstore-source.json`;

  const gitCommands = `git init
git add .
git commit -m "Natywna aplikacja ZSME Assistant na iOS (SwiftUI)"
git branch -M main
git remote add origin https://github.com/${cleanUser}/${cleanRepo}.git
git push -u origin main`;

  const copyText = async (id: string, text: string) => {
    await navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 1800);
  };

  return (
    <div className="space-y-8">
      <div className="border-b border-slate-200 dark:border-slate-800 pb-6">
        <p className="text-xs font-medium text-[#0F4C81] dark:text-sky-400">
          GitHub Actions · macos-latest · XcodeGen · $0 / miesiąc
        </p>
        <h1 className="mt-2 text-2xl sm:text-3xl font-bold tracking-tight text-slate-900 dark:text-slate-100 text-balance">
          Darmowa kompilacja natywnego pliku .ipa w chmurze bez Maca
        </h1>
        <p className="mt-2 max-w-3xl text-sm sm:text-base text-slate-600 dark:text-slate-400 leading-relaxed">
          Projekt zawiera gotowy plik konfiguracji <code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">project.yml</code> oraz
          workflow <code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">.github/workflows/build-ios-ipa.yml</code>.
          Po wrzuceniu kodu na darmowe repozytorium GitHub, serwery Apple Silicon w chmurze GitHub Actions automatycznie zbudują gotowy plik{' '}
          <strong className="font-semibold text-slate-900 dark:text-slate-100">ZSMEAssistant.ipa</strong> bez konta Apple Developer ($99/rok) i bez komputera Mac.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-5 space-y-2">
          <div className="text-xs font-mono tabular-nums text-slate-500">01. Pobranie paczki</div>
          <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">Pobierz projekt SwiftUI</h3>
          <p className="text-sm text-slate-600 dark:text-slate-400">
            Kliknij przycisk poniżej, aby pobrać archiwum ZIP zawierające kompletny kod Swift, zasoby i workflow CI.
          </p>
          <button
            onClick={onDownloadZip}
            className="mt-2 inline-flex items-center gap-2 px-3 py-2 text-xs font-medium text-white bg-[#0F4C81] hover:bg-[#0c3d68] rounded-lg transition-colors whitespace-nowrap"
          >
            <Download className="w-3.5 h-3.5" />
            Pobierz ZSME-Assistant-iOS.zip
          </button>
        </div>

        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-5 space-y-2">
          <div className="text-xs font-mono tabular-nums text-slate-500">02. Repozytorium GitHub</div>
          <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">Utwórz publiczne repo</h3>
          <p className="text-sm text-slate-600 dark:text-slate-400">
            Publiczne repozytoria na GitHubie mają nielimitowane darmowe minuty budowania na maszynach macOS (prywatne mają 2000 min/mies. za darmo).
          </p>
          <a
            href="https://github.com/new"
            target="_blank"
            rel="noreferrer"
            className="mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-[#0F4C81] dark:text-sky-400 hover:underline"
          >
            Otwórz github.com/new
            <ExternalLink className="w-3.5 h-3.5" />
          </a>
        </div>

        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-5 space-y-2">
          <div className="text-xs font-mono tabular-nums text-slate-500">03. Automatyczny build</div>
          <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">XcodeGen + xcodebuild</h3>
          <p className="text-sm text-slate-600 dark:text-slate-400">
            Po poleceniu <code className="text-xs">git push</code> runner <code className="text-xs">macos-latest</code> generuje projekt Xcode, pobiera SwiftSoup i pakuje <code className="text-xs">Payload/ZSMEAssistant.app</code> do <code className="text-xs">.ipa</code> (a workflow <code className="text-xs">deploy-testflight.yml</code> podpisuje i wysyła do TestFlight).
          </p>
        </div>

        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-5 space-y-2">
          <div className="text-xs font-mono tabular-nums text-slate-500">04. Gotowe wydanie</div>
          <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">Pobierz .ipa lub TestFlight</h3>
          <p className="text-sm text-slate-600 dark:text-slate-400">
            Po ok. 2 minutach gotowy plik <code className="text-xs">ZSMEAssistant.ipa</code> pojawia się w GitHub Releases, a po konfiguracji sekretów także bezpośrednio w aplikacji Apple TestFlight.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-4">
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <Terminal className="w-4 h-4 text-[#0F4C81] dark:text-sky-400" />
              <h2 className="text-base font-semibold text-slate-900 dark:text-slate-100">
                Wypchnięcie kodu z Windows lub Linux
              </h2>
            </div>
            <button
              onClick={() => copyText('git', gitCommands)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-slate-700 dark:text-slate-200 bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 rounded-lg transition-colors whitespace-nowrap"
            >
              {copiedId === 'git' ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
              {copiedId === 'git' ? 'Skopiowano' : 'Kopiuj polecenia'}
            </button>
          </div>
          <p className="text-xs text-slate-600 dark:text-slate-400">
            Rozpakuj pobrany plik ZIP i uruchom w folderze projektu w PowerShell (Windows) lub Terminalu (Linux):
          </p>
          <pre className="p-4 rounded-lg bg-slate-950 text-slate-100 text-xs overflow-x-auto leading-relaxed font-mono">
            {gitCommands}
          </pre>
        </div>

        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6 space-y-4">
          <h2 className="text-base font-semibold text-slate-900 dark:text-slate-100">
            Generator linków dla Twojego GitHub Releases i SideStore
          </h2>
          <p className="text-xs text-slate-600 dark:text-slate-400">
            Wpisz swój login GitHub i nazwę repozytorium, aby otrzymać bezpośredni link do źródła SideStore / AltStore oraz strony pobierania IPA:
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label className="block space-y-1">
              <span className="text-xs font-medium text-slate-700 dark:text-slate-300">Login GitHub</span>
              <input
                type="text"
                value={githubUser}
                onChange={(e) => setGithubUser(e.target.value)}
                className="w-full px-3 py-2 text-sm rounded-lg border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-950 text-slate-900 dark:text-slate-100"
              />
            </label>
            <label className="block space-y-1">
              <span className="text-xs font-medium text-slate-700 dark:text-slate-300">Nazwa repozytorium</span>
              <input
                type="text"
                value={repoName}
                onChange={(e) => setRepoName(e.target.value)}
                className="w-full px-3 py-2 text-sm rounded-lg border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-950 text-slate-900 dark:text-slate-100"
              />
            </label>
          </div>

          <div className="space-y-3 pt-2">
            <div className="p-3 rounded-lg bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800">
              <div className="flex items-center justify-between gap-2">
                <span className="text-xs font-medium text-slate-500">URL źródła SideStore / AltStore</span>
                <button
                  onClick={() => copyText('source', sideStoreSourceUrl)}
                  className="text-xs font-medium text-[#0F4C81] dark:text-sky-400 hover:underline whitespace-nowrap"
                >
                  {copiedId === 'source' ? 'Skopiowano' : 'Kopiuj URL'}
                </button>
              </div>
              <p className="mt-1 text-xs font-mono text-slate-800 dark:text-slate-200 break-all">{sideStoreSourceUrl}</p>
            </div>

            <div className="p-3 rounded-lg bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800">
              <div className="flex items-center justify-between gap-2">
                <span className="text-xs font-medium text-slate-500">Strona pobierania pliku .ipa</span>
                <button
                  onClick={() => copyText('rel', releasesUrl)}
                  className="text-xs font-medium text-[#0F4C81] dark:text-sky-400 hover:underline whitespace-nowrap"
                >
                  {copiedId === 'rel' ? 'Skopiowano' : 'Kopiuj URL'}
                </button>
              </div>
              <p className="mt-1 text-xs font-mono text-slate-800 dark:text-slate-200 break-all">{releasesUrl}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
