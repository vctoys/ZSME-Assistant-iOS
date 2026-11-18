import { useEffect, useMemo, useState } from 'react';
import {
  ArrowLeftRight,
  Calendar,
  Home,
  Radio,
  RefreshCw,
  Send,
  Settings,
} from 'lucide-react';
import type {
  ClassTimetable,
  LessonEntry,
  StudentGroup,
  SubstitutionsSnapshot,
  TimetableCatalog,
  UserRole,
} from '../types/zsme';

type PhoneTab = 'home' | 'substitutions' | 'timetable' | 'messenger' | 'settings';

const DAY_SHORT = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt'];
const DAY_FULL = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek'];

const BELL_SLOTS: Record<number, [number, number, number, number]> = {
  0: [7, 10, 7, 55],
  1: [8, 0, 8, 45],
  2: [8, 55, 9, 40],
  3: [9, 50, 10, 35],
  4: [10, 50, 11, 35],
  5: [11, 45, 12, 30],
  6: [12, 40, 13, 25],
  7: [13, 35, 14, 20],
  8: [14, 25, 15, 10],
  9: [15, 15, 16, 0],
};

function parseRangeSeconds(timeRange: string, period: number): [number, number] {
  const m = /(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})/.exec(timeRange || '');
  if (m) {
    return [
      parseInt(m[1], 10) * 3600 + parseInt(m[2], 10) * 60,
      parseInt(m[3], 10) * 3600 + parseInt(m[4], 10) * 60,
    ];
  }
  const bell = BELL_SLOTS[period] || [8, 0, 8, 45];
  return [bell[0] * 3600 + bell[1] * 60, bell[2] * 3600 + bell[3] * 60];
}

function formatCountdown(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const rem = s % 60;
  const p = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${p(m)}:${p(rem)}` : `${p(m)}:${p(rem)}`;
}

function extractClassCode(raw: string): string {
  const m = /\b([1-6][A-ZĄĆĘŁŃÓŚŹŻ]{1,5}\d?)\b/.exec(raw.toUpperCase());
  return m ? m[1] : raw;
}

function matchesGroupFilter(lesson: LessonEntry, group: StudentGroup): boolean {
  if (group === 'ALL') return true;
  if (group === 'GROUP_1') return lesson.groupTag === null || lesson.groupTag === '1/2';
  return lesson.groupTag === null || lesson.groupTag === '2/2';
}

export function IosSimulatorPanel() {
  const [phoneTab, setPhoneTab] = useState<PhoneTab>('home');
  const [catalog, setCatalog] = useState<TimetableCatalog>({ classes: [], teachers: [], rooms: [] });
  const [selectedClassUrl, setSelectedClassUrl] = useState<string>('');
  const [selectedClassName, setSelectedClassName] = useState<string>('');
  const [selectedGroup, setSelectedGroup] = useState<StudentGroup>('ALL');
  const [userRole, setUserRole] = useState<UserRole>('STUDENT');
  const [teacherAbbr, setTeacherAbbr] = useState<string>('KS');

  const [timetable, setTimetable] = useState<ClassTimetable | null>(null);
  const [substitutions, setSubstitutions] = useState<SubstitutionsSnapshot | null>(null);
  const [subFilter, setSubFilter] = useState<'my' | 'all'>('my');
  const [selectedDay, setSelectedDay] = useState<number>(() => {
    const d = new Date().getDay();
    return d >= 1 && d <= 5 ? d - 1 : 0;
  });

  const [loadingCatalog, setLoadingCatalog] = useState(true);
  const [loadingData, setLoadingData] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);
  const [now, setNow] = useState(() => new Date());

  // BLE Mesh local interactive demo state
  const [meshRunning, setMeshRunning] = useState(false);
  const [meshChannel, setMeshChannel] = useState('#ogólny');
  const [meshInput, setMeshInput] = useState('');
  const [meshMessages, setMeshMessages] = useState([
    { id: '1', sender: '3TA-Kacper', channel: '#ogólny', text: 'Wie ktoś w której sali jest dzisiaj matematyka?', hops: 1, mine: false },
    { id: '2', sender: '2TB-Marek', channel: '#ogólny', text: 'Na zastępstwach piszą że 51 bez zmian.', hops: 0, mine: false },
  ]);

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  const loadInitialData = async () => {
    setLoadingCatalog(true);
    setErrorText(null);
    try {
      const [catRes, subRes] = await Promise.all([
        fetch('/api/zsme/catalog'),
        fetch('/api/zsme/substitutions'),
      ]);
      if (!catRes.ok) throw new Error('Nie udało się pobrać listy klas z plan.zsme.pl');
      const catJson = (await catRes.json()) as TimetableCatalog;
      setCatalog(catJson);
      if (subRes.ok) {
        setSubstitutions((await subRes.json()) as SubstitutionsSnapshot);
      }
      if (catJson.classes.length > 0 && !selectedClassUrl) {
        const first = catJson.classes[0];
        setSelectedClassUrl(first.url);
        setSelectedClassName(first.name);
      }
    } catch (e) {
      setErrorText(e instanceof Error ? e.message : 'Błąd połączenia z serwerami ZSME');
    } finally {
      setLoadingCatalog(false);
    }
  };

  useEffect(() => {
    loadInitialData();
  }, []);

  useEffect(() => {
    if (!selectedClassUrl) return;
    let cancelled = false;
    setLoadingData(true);
    fetch(`/api/zsme/timetable?url=${encodeURIComponent(selectedClassUrl)}&name=${encodeURIComponent(selectedClassName)}&category=CLASS`)
      .then((r) => r.json())
      .then((data: ClassTimetable) => {
        if (!cancelled) setTimetable(data);
      })
      .catch(() => {
        if (!cancelled) setErrorText('Nie udało się pobrać wybranego planu lekcji');
      })
      .finally(() => {
        if (!cancelled) setLoadingData(false);
      });
    return () => {
      cancelled = true;
    };
  }, [selectedClassUrl, selectedClassName]);

  const classCode = extractClassCode(selectedClassName);

  const filteredSubstitutions = useMemo(() => {
    const all = substitutions?.items || [];
    if (subFilter === 'all' || !classCode) return all;
    return all.filter((item) => {
      const text = `${item.className} ${item.subject} ${item.note}`.toUpperCase();
      return text.includes(classCode.toUpperCase());
    });
  }, [substitutions, subFilter, classCode]);

  const todayWeekdayIndex = useMemo(() => {
    const dow = now.getDay();
    return dow >= 1 && dow <= 5 ? dow - 1 : null;
  }, [now]);

  const todayLessons = useMemo(() => {
    const dIdx = todayWeekdayIndex ?? 0;
    const day = timetable?.days.find((d) => d.dayIndex === dIdx);
    return (day?.lessons || []).filter((l) => matchesGroupFilter(l, selectedGroup));
  }, [timetable, todayWeekdayIndex, selectedGroup]);

  const liveBanner = useMemo(() => {
    if (!todayLessons.length) {
      return {
        label: todayWeekdayIndex === null ? 'Weekend' : 'Brak zajęć dzisiaj',
        countdown: '--:--',
        detail: 'Sprawdź plan na kolejne dni lub zastępstwa.',
        progress: 0,
      };
    }
    const nowSec = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
    const slots = todayLessons.map((l) => {
      const [start, end] = parseRangeSeconds(l.timeRange, l.period);
      return { lesson: l, start, end };
    });

    const current = slots.find((s) => nowSec >= s.start && nowSec < s.end);
    if (current) {
      const rem = current.end - nowSec;
      const tot = Math.max(1, current.end - current.start);
      return {
        label: `Trwa lekcja ${current.lesson.period}`,
        countdown: formatCountdown(rem),
        detail: `${current.lesson.subject} · Sala ${current.lesson.room || '—'}`,
        progress: Math.min(1, Math.max(0, (tot - rem) / tot)),
      };
    }
    if (nowSec < slots[0].start) {
      return {
        label: 'Przed lekcjami',
        countdown: formatCountdown(slots[0].start - nowSec),
        detail: `Pierwsza: ${slots[0].lesson.subject} (${slots[0].lesson.timeRange})`,
        progress: 0,
      };
    }
    for (let i = 0; i < slots.length - 1; i++) {
      if (nowSec >= slots[i].end && nowSec < slots[i + 1].start) {
        const rem = slots[i + 1].start - nowSec;
        const tot = Math.max(1, slots[i + 1].start - slots[i].end);
        return {
          label: 'Przerwa międzylekcyjna',
          countdown: formatCountdown(rem),
          detail: `Następna: ${slots[i + 1].lesson.subject} · Sala ${slots[i + 1].lesson.room || '—'}`,
          progress: Math.min(1, Math.max(0, (tot - rem) / tot)),
        };
      }
    }
    return {
      label: 'Koniec zajęć na dziś',
      countdown: '00:00',
      detail: 'Wszystkie lekcje zakończone.',
      progress: 1,
    };
  }, [todayLessons, todayWeekdayIndex, now]);

  const selectedDayLessons = useMemo(() => {
    const day = timetable?.days.find((d) => d.dayIndex === selectedDay);
    return (day?.lessons || []).filter((l) => matchesGroupFilter(l, selectedGroup));
  }, [timetable, selectedDay, selectedGroup]);

  const handleDownloadIcs = async () => {
    if (!timetable) return;
    const filteredDays = timetable.days.map((d) => ({
      dayIndex: d.dayIndex,
      lessons: d.lessons.filter((l) => matchesGroupFilter(l, selectedGroup)),
    }));
    const res = await fetch('/api/export-ics', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ className: classCode || timetable.className, days: filteredDays }),
    });
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `plan-${classCode || 'zsme'}.ics`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleSendMesh = () => {
    const txt = meshInput.trim();
    if (!txt) return;
    setMeshInput('');
    setMeshMessages((prev) => [
      ...prev,
      {
        id: String(Date.now()),
        sender: classCode ? `${classCode}-Ja` : 'Uczeń-Ja',
        channel: meshChannel,
        text: txt,
        hops: 0,
        mine: true,
      },
    ]);
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-stretch">
      {/* Left Column: Live Data Controls & Architecture Summary */}
      <div className="lg:col-span-7 flex flex-col justify-between space-y-6">
        <div className="space-y-4">
          <p className="text-xs font-medium text-[#0F4C81] dark:text-sky-400">
            Natywna aplikacja SwiftUI · Połączona na żywo z plan.zsme.pl i sekretariat.zsme.pl
          </p>
          <h1 className="text-3xl sm:text-4xl font-bold tracking-tight text-slate-900 dark:text-slate-100 text-balance">
            ZSME Assistant przepisany natywnie na iOS
          </h1>
          <p className="text-sm sm:text-base text-slate-600 dark:text-slate-400 leading-relaxed max-w-2xl">
            Pełny port aplikacji z Androida (<code className="text-xs bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded">dniesobski/ZSME-Assistant</code>) do języka Swift i SwiftUI. Kompilowany za darmo w chmurze GitHub Actions bez komputera Mac i wgrywany na iPhone&apos;a z Windowsa lub Linuksa bez jailbreaka.
          </p>
        </div>

        {/* Interactive School Control Panel */}
        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-5 space-y-4">
          <div className="flex items-center justify-between gap-4 border-b border-slate-100 dark:border-slate-800 pb-3">
            <div>
              <h2 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
                Podgląd na żywo z prawdziwych serwerów ZSME
              </h2>
              <p className="text-xs text-slate-500">
                Zmień klasę lub grupę, aby przetestować parser Optivum i tablicę zastępstw w symulatorze obok
              </p>
            </div>
            <button
              onClick={loadInitialData}
              disabled={loadingCatalog}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg border border-slate-200 dark:border-slate-700 text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors whitespace-nowrap"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${loadingCatalog ? 'animate-spin' : ''}`} />
              Odśwież dane
            </button>
          </div>

          {errorText && (
            <div className="p-3 rounded-lg bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900 text-xs text-red-700 dark:text-red-300">
              {errorText}
            </div>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <label className="block space-y-1.5">
              <span className="text-xs font-medium text-slate-700 dark:text-slate-300">
                Klasa z plan.zsme.pl ({catalog.classes.length})
              </span>
              <select
                value={selectedClassUrl}
                onChange={(e) => {
                  const found = catalog.classes.find((c) => c.url === e.target.value);
                  if (found) {
                    setSelectedClassUrl(found.url);
                    setSelectedClassName(found.name);
                  }
                }}
                className="w-full px-3 py-2 text-sm rounded-lg border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-950 text-slate-900 dark:text-slate-100"
              >
                {catalog.classes.map((c) => (
                  <option key={c.url} value={c.url}>
                    {c.name}
                  </option>
                ))}
              </select>
            </label>

            <div className="space-y-1.5">
              <span className="text-xs font-medium text-slate-700 dark:text-slate-300 block">Grupa uczniowska</span>
              <div className="grid grid-cols-3 gap-1 p-1 bg-slate-100 dark:bg-slate-950 rounded-lg border border-slate-200 dark:border-slate-800">
                {(
                  [
                    ['ALL', 'Cała'],
                    ['GROUP_1', 'Gr. 1'],
                    ['GROUP_2', 'Gr. 2'],
                  ] as const
                ).map(([val, label]) => (
                  <button
                    key={val}
                    onClick={() => setSelectedGroup(val)}
                    className={`py-1.5 text-xs font-medium rounded-md transition-colors whitespace-nowrap ${
                      selectedGroup === val
                        ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
                        : 'text-slate-600 dark:text-slate-400'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-3 pt-2 border-t border-slate-100 dark:border-slate-800 text-xs text-slate-600 dark:text-slate-400">
            <div className="flex items-center gap-2 font-mono tabular-nums">
              <span>Klasy: {catalog.classes.length}</span>
              <span aria-hidden="true">·</span>
              <span>Nauczyciele: {catalog.teachers.length}</span>
              <span aria-hidden="true">·</span>
              <span>Sale: {catalog.rooms.length}</span>
              <span aria-hidden="true">·</span>
              <span>Zastępstwa: {substitutions?.items.length ?? 0}</span>
            </div>
            <button
              onClick={handleDownloadIcs}
              disabled={!timetable}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-[#0F4C81] dark:text-sky-400 hover:bg-[#0F4C81]/10 rounded-lg transition-colors whitespace-nowrap disabled:opacity-40"
            >
              <Calendar className="w-3.5 h-3.5" />
              Eksportuj plan .ics
            </button>
          </div>
        </div>

        {/* 4-cell KPI/Capability Strip */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3.5">
            <div className="text-xs text-slate-500">Technologia</div>
            <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-slate-100">SwiftUI + SwiftSoup</div>
          </div>
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3.5">
            <div className="text-xs text-slate-500">Kalendarz iOS</div>
            <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-slate-100">EventKit + .ics</div>
          </div>
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3.5">
            <div className="text-xs text-slate-500">Komunikator</div>
            <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-slate-100">CoreBluetooth Mesh</div>
          </div>
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3.5">
            <div className="text-xs text-slate-500">Kompilacja IPA</div>
            <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-slate-100">GitHub Actions $0</div>
          </div>
        </div>
      </div>

      {/* Right Column: Interactive iPhone 16 Frame */}
      <div className="lg:col-span-5 flex justify-center">
        <div className="w-full max-w-[360px] bg-slate-900 rounded-[44px] p-3 shadow-xl border-4 border-slate-800 flex flex-col h-[700px]">
          {/* Dynamic Island */}
          <div className="flex items-center justify-between px-5 pt-1 pb-2 text-[11px] font-medium text-white">
            <span className="font-mono tabular-nums">
              {now.toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit' })}
            </span>
            <div className="w-24 h-5 bg-black rounded-full" />
            <span className="text-[10px] text-slate-300">5G</span>
          </div>

          {/* iPhone Screen */}
          <div className="flex-1 bg-slate-100 dark:bg-slate-950 rounded-[32px] overflow-hidden flex flex-col">
            {/* Screen Header */}
            <div className="px-4 py-3 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between">
              <span className="text-sm font-bold text-slate-900 dark:text-slate-100">
                {phoneTab === 'home' && 'ZSME Assistant'}
                {phoneTab === 'substitutions' && 'Zastępstwa'}
                {phoneTab === 'timetable' && (classCode || 'Plan lekcji')}
                {phoneTab === 'messenger' && 'Komunikator BLE'}
                {phoneTab === 'settings' && 'Ustawienia'}
              </span>
              <span className="text-[11px] text-slate-500 font-mono">
                {userRole === 'STUDENT' ? classCode || 'Klasa' : teacherAbbr}
              </span>
            </div>

            {/* Scrollable Body */}
            <div className="flex-1 overflow-y-auto p-3.5 space-y-3">
              {phoneTab === 'home' && (
                <>
                  <div className="bg-white dark:bg-slate-900 rounded-2xl p-3.5 border border-slate-200/80 dark:border-slate-800 space-y-2">
                    <div className="flex items-center justify-between text-xs">
                      <span className="font-semibold text-[#0F4C81] dark:text-sky-400">{liveBanner.label}</span>
                      <span className="text-slate-500 font-mono tabular-nums">
                        {DAY_FULL[todayWeekdayIndex ?? 0]}
                      </span>
                    </div>
                    <div className="text-3xl font-bold font-mono tabular-nums text-slate-900 dark:text-slate-100">
                      {liveBanner.countdown}
                    </div>
                    <div className="w-full h-1.5 bg-slate-200 dark:bg-slate-800 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-[#0F4C81] dark:bg-sky-400 transition-all"
                        style={{ width: `${Math.round(liveBanner.progress * 100)}%` }}
                      />
                    </div>
                    <p className="text-xs text-slate-600 dark:text-slate-400">{liveBanner.detail}</p>
                  </div>

                  <div className="space-y-2">
                    <div className="flex items-center justify-between px-1">
                      <span className="text-xs font-semibold text-slate-700 dark:text-slate-300">Dzisiejszy plan</span>
                      <button
                        onClick={() => setPhoneTab('timetable')}
                        className="text-xs text-[#0F4C81] dark:text-sky-400 font-medium"
                      >
                        Cały tydzień
                      </button>
                    </div>
                    {loadingData ? (
                      <div className="text-xs text-slate-500 p-3">Wczytywanie...</div>
                    ) : todayLessons.length === 0 ? (
                      <div className="bg-white dark:bg-slate-900 rounded-xl p-3 text-xs text-slate-500 border border-slate-200/80 dark:border-slate-800">
                        Brak lekcji w tym dniu.
                      </div>
                    ) : (
                      todayLessons.map((l, idx) => (
                        <div
                          key={`${l.period}-${idx}`}
                          className="bg-white dark:bg-slate-900 rounded-xl p-3 border border-slate-200/80 dark:border-slate-800 flex items-center gap-3"
                        >
                          <div className="w-9 text-center shrink-0">
                            <div className="text-sm font-bold font-mono tabular-nums text-[#0F4C81] dark:text-sky-400">
                              {l.period}
                            </div>
                            <div className="text-[10px] font-mono tabular-nums text-slate-400">
                              {l.timeRange.split('-')[0]}
                            </div>
                          </div>
                          <div className="min-w-0 flex-1">
                            <div className="text-xs font-semibold text-slate-900 dark:text-slate-100 truncate">
                              {l.subject}
                            </div>
                            <div className="text-[11px] text-slate-500 truncate">
                              {l.teacher || '—'} · Sala {l.room || '—'}
                              {l.groupTag ? ` · ${l.groupTag}` : ''}
                            </div>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </>
              )}

              {phoneTab === 'substitutions' && (
                <>
                  <div className="grid grid-cols-2 gap-1 p-1 bg-slate-200/70 dark:bg-slate-900 rounded-lg">
                    <button
                      onClick={() => setSubFilter('my')}
                      className={`py-1.5 text-xs font-medium rounded-md ${
                        subFilter === 'my'
                          ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
                          : 'text-slate-600 dark:text-slate-400'
                      }`}
                    >
                      Moja klasa ({classCode || '—'})
                    </button>
                    <button
                      onClick={() => setSubFilter('all')}
                      className={`py-1.5 text-xs font-medium rounded-md ${
                        subFilter === 'all'
                          ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 shadow-sm'
                          : 'text-slate-600 dark:text-slate-400'
                      }`}
                    >
                      Wszystkie ({substitutions?.items.length ?? 0})
                    </button>
                  </div>

                  {substitutions?.dateHeading && (
                    <div className="text-xs font-semibold text-slate-700 dark:text-slate-300 px-1">
                      {substitutions.dateHeading}
                    </div>
                  )}

                  {substitutions?.announcements?.slice(0, 2).map((info, i) => (
                    <div
                      key={i}
                      className="bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded-xl p-2.5 text-[11px] text-amber-900 dark:text-amber-200"
                    >
                      {info}
                    </div>
                  ))}

                  {filteredSubstitutions.length === 0 ? (
                    <div className="bg-white dark:bg-slate-900 rounded-xl p-4 text-center space-y-2 border border-slate-200 dark:border-slate-800">
                      <img
                        src="/src/assets/images/img_no_substitutions.jpg"
                        alt="Brak zastępstw"
                        referrerPolicy="no-referrer"
                        className="w-24 h-24 mx-auto rounded-xl object-cover"
                      />
                      <p className="text-xs text-slate-500">Brak zastępstw dla wybranego filtra.</p>
                    </div>
                  ) : (
                    filteredSubstitutions.map((sub) => (
                      <div
                        key={sub.id}
                        className="bg-white dark:bg-slate-900 rounded-xl p-3 border border-slate-200/80 dark:border-slate-800 space-y-1"
                      >
                        <div className="flex items-center justify-between text-xs">
                          <span className={`font-bold ${sub.isCancellation ? 'text-red-600' : 'text-[#0F4C81] dark:text-sky-400'}`}>
                            {sub.className || 'Ogólne'} · Lekcja {sub.period}
                          </span>
                          {sub.room && <span className="text-[11px] text-slate-500">Sala {sub.room}</span>}
                        </div>
                        {sub.subject && (
                          <div className="text-xs font-medium text-slate-900 dark:text-slate-100">{sub.subject}</div>
                        )}
                        <div className="text-[11px] text-slate-500">
                          {sub.absentTeacher ? `${sub.absentTeacher} → ` : ''}
                          <span className={sub.isCancellation ? 'text-red-600 font-medium' : 'text-emerald-700 dark:text-emerald-400 font-medium'}>
                            {sub.substituteTeacher || sub.note}
                          </span>
                        </div>
                      </div>
                    ))
                  )}
                </>
              )}

              {phoneTab === 'timetable' && (
                <>
                  <div className="grid grid-cols-5 gap-1">
                    {DAY_SHORT.map((lbl, idx) => (
                      <button
                        key={lbl}
                        onClick={() => setSelectedDay(idx)}
                        className={`py-1.5 text-xs font-semibold rounded-lg transition-colors ${
                          selectedDay === idx
                            ? 'bg-[#0F4C81] text-white'
                            : 'bg-white dark:bg-slate-900 text-slate-700 dark:text-slate-300 border border-slate-200 dark:border-slate-800'
                        }`}
                      >
                        {lbl}
                      </button>
                    ))}
                  </div>

                  {selectedDayLessons.length === 0 ? (
                    <div className="bg-white dark:bg-slate-900 rounded-xl p-4 text-xs text-slate-500 border border-slate-200 dark:border-slate-800 text-center">
                      Brak lekcji w dniu {DAY_FULL[selectedDay]}.
                    </div>
                  ) : (
                    selectedDayLessons.map((l, idx) => (
                      <div
                        key={`${l.period}-${idx}`}
                        className="bg-white dark:bg-slate-900 rounded-xl p-3 border border-slate-200/80 dark:border-slate-800 flex items-center gap-3"
                      >
                        <div className="w-14 shrink-0">
                          <div className="text-sm font-bold font-mono tabular-nums text-[#0F4C81] dark:text-sky-400">
                            {l.period}
                          </div>
                          <div className="text-[10px] font-mono tabular-nums text-slate-400">{l.timeRange}</div>
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="text-xs font-semibold text-slate-900 dark:text-slate-100">{l.subject}</div>
                          <div className="text-[11px] text-slate-500">
                            {l.teacher || '—'} · Sala {l.room || '—'}
                            {l.groupTag ? ` · ${l.groupTag}` : ''}
                          </div>
                        </div>
                      </div>
                    ))
                  )}
                </>
              )}

              {phoneTab === 'messenger' && (
                <div className="flex flex-col h-full space-y-2.5">
                  <div className="bg-white dark:bg-slate-900 rounded-xl p-2.5 border border-slate-200 dark:border-slate-800 flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-slate-900 dark:text-slate-100">
                        {meshRunning ? 'Aktywna sieć BLE Mesh' : 'Radio BLE wyłączone'}
                      </div>
                      <div className="text-[10px] text-slate-500 font-mono">
                        CoreBluetooth · TTL=5 · 20B ATT
                      </div>
                    </div>
                    <button
                      onClick={() => setMeshRunning((v) => !v)}
                      className={`px-2.5 py-1 text-[11px] font-medium rounded-lg text-white ${
                        meshRunning ? 'bg-slate-600' : 'bg-[#0F4C81]'
                      }`}
                    >
                      {meshRunning ? 'Stop' : 'Start BLE'}
                    </button>
                  </div>

                  <div className="flex gap-1.5 overflow-x-auto pb-1">
                    {['#ogólny', '@prywatne', '#zastępstwa', '#pomoc'].map((ch) => (
                      <button
                        key={ch}
                        onClick={() => setMeshChannel(ch)}
                        className={`px-2.5 py-1 text-[11px] font-medium rounded-lg whitespace-nowrap ${
                          meshChannel === ch
                            ? 'bg-[#0F4C81] text-white'
                            : 'bg-white dark:bg-slate-900 text-slate-600 dark:text-slate-400 border border-slate-200 dark:border-slate-800'
                        }`}
                      >
                        {ch}
                      </button>
                    ))}
                  </div>

                  <div className="flex-1 space-y-2">
                    {meshMessages
                      .filter((m) => m.channel === meshChannel)
                      .map((m) => (
                        <div key={m.id} className={`flex flex-col ${m.mine ? 'items-end' : 'items-start'}`}>
                          <span className="text-[10px] text-slate-500 mb-0.5">
                            {m.sender}
                            {m.hops > 0 ? ` · ${m.hops} skok` : ''}
                          </span>
                          <div
                            className={`px-3 py-2 rounded-2xl text-xs max-w-[85%] ${
                              m.mine
                                ? 'bg-[#0F4C81] text-white'
                                : 'bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 border border-slate-200 dark:border-slate-800'
                            }`}
                          >
                            {m.text}
                          </div>
                        </div>
                      ))}
                  </div>

                  <div className="flex gap-1.5 pt-1">
                    <input
                      type="text"
                      value={meshInput}
                      onChange={(e) => setMeshInput(e.target.value)}
                      onKeyDown={(e) => e.key === 'Enter' && handleSendMesh()}
                      placeholder={`Wiadomość w ${meshChannel}...`}
                      className="flex-1 px-2.5 py-1.5 text-xs rounded-lg border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100"
                    />
                    <button
                      onClick={handleSendMesh}
                      className="p-2 rounded-lg bg-[#0F4C81] text-white"
                      aria-label="Wyślij"
                    >
                      <Send className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              )}

              {phoneTab === 'settings' && (
                <div className="space-y-3 text-xs">
                  <div className="bg-white dark:bg-slate-900 rounded-xl p-3 border border-slate-200 dark:border-slate-800 space-y-2">
                    <div className="font-semibold text-slate-900 dark:text-slate-100">Tryb aplikacji</div>
                    <div className="grid grid-cols-2 gap-1 p-1 bg-slate-100 dark:bg-slate-950 rounded-lg">
                      <button
                        onClick={() => setUserRole('STUDENT')}
                        className={`py-1.5 rounded-md font-medium ${
                          userRole === 'STUDENT' ? 'bg-white dark:bg-slate-800 shadow-sm' : 'text-slate-500'
                        }`}
                      >
                        Uczeń
                      </button>
                      <button
                        onClick={() => setUserRole('TEACHER')}
                        className={`py-1.5 rounded-md font-medium ${
                          userRole === 'TEACHER' ? 'bg-white dark:bg-slate-800 shadow-sm' : 'text-slate-500'
                        }`}
                      >
                        Nauczyciel
                      </button>
                    </div>
                  </div>

                  {userRole === 'TEACHER' && (
                    <div className="bg-white dark:bg-slate-900 rounded-xl p-3 border border-slate-200 dark:border-slate-800 space-y-1.5">
                      <div className="font-semibold text-slate-900 dark:text-slate-100">Skrót nauczyciela</div>
                      <input
                        type="text"
                        value={teacherAbbr}
                        onChange={(e) => setTeacherAbbr(e.target.value.toUpperCase())}
                        className="w-full px-2.5 py-1.5 rounded-lg border border-slate-300 dark:border-slate-700 bg-slate-50 dark:bg-slate-950"
                      />
                    </div>
                  )}

                  <div className="bg-white dark:bg-slate-900 rounded-xl p-3 border border-slate-200 dark:border-slate-800 space-y-1">
                    <div className="font-semibold text-slate-900 dark:text-slate-100">Źródła danych</div>
                    <div className="text-slate-500 font-mono text-[11px]">https://plan.zsme.pl/</div>
                    <div className="text-slate-500 font-mono text-[11px]">https://sekretariat.zsme.pl/tv.php</div>
                  </div>
                </div>
              )}
            </div>

            {/* Bottom iOS Tab Bar */}
            <div className="bg-white/95 dark:bg-slate-900/95 border-t border-slate-200 dark:border-slate-800 grid grid-cols-5 px-1 py-1.5">
              {(
                [
                  ['home', 'Główna', Home],
                  ['substitutions', 'Zastępstwa', ArrowLeftRight],
                  ['timetable', 'Plan', Calendar],
                  ['messenger', 'Czat BLE', Radio],
                  ['settings', 'Opcje', Settings],
                ] as const
              ).map(([key, label, Icon]) => {
                const active = phoneTab === key;
                return (
                  <button
                    key={key}
                    onClick={() => setPhoneTab(key)}
                    className={`flex flex-col items-center justify-center py-1 rounded-lg transition-colors ${
                      active ? 'text-[#0F4C81] dark:text-sky-400' : 'text-slate-400 dark:text-slate-500'
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    <span className="text-[10px] font-medium mt-0.5 truncate max-w-full">{label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
