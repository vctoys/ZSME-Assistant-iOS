import { useEffect, useState } from 'react';
import { Download, Moon, Sun } from 'lucide-react';
import { IosSimulatorPanel } from './components/IosSimulatorPanel';
import { SwiftCodeExplorer } from './components/SwiftCodeExplorer';
import { CloudBuildGuide } from './components/CloudBuildGuide';
import { IphoneInstallGuide } from './components/IphoneInstallGuide';

type SectionKey = 'preview' | 'code' | 'cloud' | 'install';

export default function App() {
  const [section, setSection] = useState<SectionKey>('preview');
  const [dark, setDark] = useState(false);

  useEffect(() => {
    document.documentElement.classList.toggle('dark', dark);
  }, [dark]);

  const handleDownloadZip = () => {
    window.location.href = '/api/export-ios-zip';
  };

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950 text-slate-900 dark:text-slate-100 flex flex-col">
      {/* 3-Zone Top Bar Contract */}
      <header className="sticky top-0 z-30 bg-white/90 dark:bg-slate-900/90 backdrop-blur-md border-b border-slate-200 dark:border-slate-800">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between gap-8">
          <button
            onClick={() => setSection('preview')}
            className="text-lg font-bold tracking-tight text-slate-900 dark:text-slate-100 whitespace-nowrap shrink-0"
          >
            ZSME Assistant iOS
          </button>

          <nav className="hidden md:flex items-center gap-6 text-sm font-medium">
            {(
              [
                ['preview', 'Podgląd iOS'],
                ['code', 'Kod Swift'],
                ['cloud', 'Chmura GitHub'],
                ['install', 'Instalacja iPhone'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setSection(key)}
                className={`whitespace-nowrap shrink-0 py-1 border-b-2 transition-colors ${
                  section === key
                    ? 'border-[#0F4C81] dark:border-sky-400 text-slate-900 dark:text-slate-100'
                    : 'border-transparent text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100'
                }`}
              >
                {label}
              </button>
            ))}
          </nav>

          <div className="flex items-center gap-2.5 shrink-0">
            <button
              onClick={() => setDark((d) => !d)}
              aria-label="Przełącz motyw"
              className="p-2 rounded-lg text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            >
              {dark ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
            </button>
            <button
              onClick={handleDownloadZip}
              className="inline-flex items-center gap-2 px-4 py-2 text-xs font-medium text-white bg-[#0F4C81] hover:bg-[#0c3d68] rounded-lg transition-colors whitespace-nowrap shrink-0"
            >
              <Download className="w-3.5 h-3.5" />
              Pobierz projekt .zip
            </button>
          </div>
        </div>

        {/* Mobile Nav Row */}
        <div className="md:hidden border-t border-slate-200 dark:border-slate-800 px-4 py-2 flex items-center gap-4 overflow-x-auto text-xs font-medium">
          {(
            [
              ['preview', 'Podgląd iOS'],
              ['code', 'Kod Swift'],
              ['cloud', 'Chmura GitHub'],
              ['install', 'Instalacja iPhone'],
            ] as const
          ).map(([key, label]) => (
            <button
              key={key}
              onClick={() => setSection(key)}
              className={`whitespace-nowrap shrink-0 pb-1 border-b-2 ${
                section === key
                  ? 'border-[#0F4C81] dark:border-sky-400 text-slate-900 dark:text-slate-100'
                  : 'border-transparent text-slate-600 dark:text-slate-400'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </header>

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 py-8">
        {section === 'preview' && <IosSimulatorPanel />}
        {section === 'code' && <SwiftCodeExplorer />}
        {section === 'cloud' && <CloudBuildGuide onDownloadZip={handleDownloadZip} />}
        {section === 'install' && <IphoneInstallGuide />}
      </main>

      <footer className="border-t border-slate-200 dark:border-slate-800 bg-white dark:bg-slate-900/50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-5 flex flex-col sm:flex-row items-center justify-between gap-2 text-xs text-slate-500">
          <span>ZSME Assistant iOS · Przepisano z dniesobski/ZSME-Assistant na Swift / SwiftUI</span>
          <span>Darmowa kompilacja IPA przez GitHub Actions · Instalacja bez jailbreaka</span>
        </div>
      </footer>
    </div>
  );
}
