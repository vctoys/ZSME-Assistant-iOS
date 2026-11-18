import { useEffect, useMemo, useState } from 'react';
import { Check, Copy, FileCode2, FolderOpen, Search } from 'lucide-react';
import type { IosProjectFile } from '../types/zsme';

export function SwiftCodeExplorer() {
  const [files, setFiles] = useState<IosProjectFile[]>([]);
  const [selectedPath, setSelectedPath] = useState<string>('ZSMEAssistant/Views/HomeView.swift');
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    fetch('/api/ios-files')
      .then((res) => res.json())
      .then((data: { files?: IosProjectFile[] }) => {
        const list = data.files || [];
        setFiles(list);
        if (list.length > 0 && !list.some((f) => f.path === selectedPath)) {
          const firstSwift = list.find((f) => f.path.endsWith('.swift')) || list[0];
          setSelectedPath(firstSwift.path);
        }
      })
      .finally(() => setLoading(false));
  }, []);

  const filteredFiles = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return files;
    return files.filter((f) => f.path.toLowerCase().includes(q));
  }, [files, query]);

  const activeFile = useMemo(
    () => files.find((f) => f.path === selectedPath) || filteredFiles[0] || null,
    [files, filteredFiles, selectedPath]
  );

  const handleCopy = async () => {
    if (!activeFile?.content) return;
    await navigator.clipboard.writeText(activeFile.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  };

  return (
    <div className="space-y-6">
      <div className="border-b border-slate-200 dark:border-slate-800 pb-5">
        <p className="text-xs font-medium text-[#0F4C81] dark:text-sky-400">
          Swift 5.9 · SwiftUI · SwiftSoup · CoreBluetooth · EventKit · iOS 16.0+
        </p>
        <h1 className="mt-2 text-2xl sm:text-3xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
          Kod źródłowy natywnej aplikacji iOS
        </h1>
        <p className="mt-1.5 text-sm text-slate-600 dark:text-slate-400">
          Przeglądaj wszystkie pliki przepisanej aplikacji z Androida (Kotlin/Compose) na natywny iOS (Swift/SwiftUI).
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-stretch">
        <div className="lg:col-span-4 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl flex flex-col overflow-hidden">
          <div className="p-3 border-b border-slate-200 dark:border-slate-800">
            <div className="relative">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Filtruj pliki Swift..."
                className="w-full pl-9 pr-3 py-2 text-xs rounded-lg border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-950 text-slate-900 dark:text-slate-100"
              />
            </div>
          </div>

          <div className="overflow-y-auto max-h-[600px] divide-y divide-slate-100 dark:divide-slate-800/60">
            {loading ? (
              <div className="p-4 text-xs text-slate-500">Wczytywanie drzewa projektu...</div>
            ) : filteredFiles.length === 0 ? (
              <div className="p-4 text-xs text-slate-500">Brak pasujących plików.</div>
            ) : (
              filteredFiles.map((file) => {
                const isSelected = activeFile?.path === file.path;
                return (
                  <button
                    key={file.path}
                    onClick={() => setSelectedPath(file.path)}
                    className={`w-full text-left px-3.5 py-2.5 flex items-center justify-between gap-2 text-xs transition-colors ${
                      isSelected
                        ? 'bg-[#0F4C81]/10 dark:bg-sky-500/15 text-[#0F4C81] dark:text-sky-300 font-semibold'
                        : 'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800/60'
                    }`}
                  >
                    <span className="flex items-center gap-2 min-w-0">
                      <FileCode2 className="w-3.5 h-3.5 shrink-0 opacity-70" />
                      <span className="truncate font-mono">{file.path}</span>
                    </span>
                    <span className="text-[11px] font-mono tabular-nums text-slate-400 shrink-0">
                      {(file.size / 1024).toFixed(1)} KB
                    </span>
                  </button>
                );
              })
            )}
          </div>
        </div>

        <div className="lg:col-span-8 bg-slate-950 border border-slate-800 rounded-xl flex flex-col overflow-hidden min-h-[520px]">
          <div className="px-4 py-3 border-b border-slate-800 flex items-center justify-between gap-4 bg-slate-900/80">
            <div className="flex items-center gap-2 min-w-0">
              <FolderOpen className="w-4 h-4 text-sky-400 shrink-0" />
              <span className="text-xs font-mono text-slate-200 truncate">
                {activeFile ? `ios-app/${activeFile.path}` : 'Wybierz plik'}
              </span>
            </div>
            {activeFile?.content && (
              <button
                onClick={handleCopy}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-slate-200 bg-slate-800 hover:bg-slate-700 rounded-lg transition-colors whitespace-nowrap shrink-0"
              >
                {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
                {copied ? 'Skopiowano' : 'Kopiuj plik'}
              </button>
            )}
          </div>

          <div className="flex-1 overflow-auto p-4 max-h-[600px]">
            {activeFile?.isBinary ? (
              <div className="text-xs text-slate-400 font-mono">
                Plik binarny ({activeFile.path}, {(activeFile.size / 1024).toFixed(1)} KB)
              </div>
            ) : (
              <pre className="text-xs font-mono text-slate-200 leading-relaxed whitespace-pre">
                {activeFile?.content || ''}
              </pre>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
