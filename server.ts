import express from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import * as cheerio from 'cheerio';
import JSZip from 'jszip';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PLAN_BASE_URL = 'https://plan.zsme.pl/';
const SUBSTITUTIONS_URL = 'https://sekretariat.zsme.pl/tv.php';
const DEFAULT_DAYS = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek'];

const GROUP1_MARKERS = ['1/2', 'gr.1', 'gr. 1', 'gr 1', 'grupa 1', '-1/2', '/1', '(1)', 'g1', 'gr1'];
const GROUP2_MARKERS = ['2/2', 'gr.2', 'gr. 2', 'gr 2', 'grupa 2', '-2/2', '/2', '(2)', 'g2', 'gr2'];

function detectGroupTag(text: string): string | null {
  const lower = text.toLowerCase();
  const hasToken = (marker: string) => {
    if (marker === '/1' || marker === '/2') {
      const escaped = marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return new RegExp(`(?<!\\d)${escaped}(?!\\d)`).test(lower);
    }
    return lower.includes(marker);
  };
  if (GROUP1_MARKERS.some(hasToken)) return '1/2';
  if (GROUP2_MARKERS.some(hasToken)) return '2/2';
  return null;
}

function foldPolish(text: string): string {
  const map: Record<string, string> = {
    ą: 'a', ć: 'c', ę: 'e', ł: 'l', ń: 'n', ó: 'o', ś: 's', ź: 'z', ż: 'z',
    Ą: 'A', Ć: 'C', Ę: 'E', Ł: 'L', Ń: 'N', Ó: 'O', Ś: 'S', Ź: 'Z', Ż: 'Z',
  };
  return text.replace(/[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]/g, (ch) => map[ch] ?? ch);
}

function isCancellationText(text: string): boolean {
  const folded = foldPolish(text).toLowerCase();
  const keywords = [
    'odwolan', 'zwolnion', 'do domu', 'przychodzi pozniej', 'przychodza pozniej',
    'konczy szybciej', 'koncza szybciej', 'konczy wczesniej', 'koncza wczesniej',
    'brak zajec', 'nie ma lekcji', 'lekcja odwolana', 'zajecia odwolane',
  ];
  return keywords.some((k) => folded.includes(k));
}

async function fetchText(url: string): Promise<{ finalUrl: string; html: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
        'Accept-Language': 'pl-PL,pl;q=0.9,en;q=0.8',
      },
    });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status} z ${url}`);
    }
    const buf = await res.arrayBuffer();
    const contentType = res.headers.get('content-type') || '';
    const peek = Buffer.from(buf.slice(0, 2048)).toString('latin1').toLowerCase();
    let charset = 'utf-8';
    if (contentType.toLowerCase().includes('iso-8859-2') || peek.includes('iso-8859-2')) {
      charset = 'iso-8859-2';
    } else if (contentType.toLowerCase().includes('windows-1250') || peek.includes('windows-1250')) {
      charset = 'windows-1250';
    }
    const decoder = new TextDecoder(charset);
    return { finalUrl: res.url || url, html: decoder.decode(buf) };
  } finally {
    clearTimeout(timer);
  }
}

function resolveUrl(base: string, rel: string): string {
  try {
    return new URL(rel, base).toString();
  } catch {
    return rel;
  }
}

function parseCatalog(html: string, baseUrl: string) {
  const $ = cheerio.load(html);
  const classesMap = new Map<string, { id: string; name: string; url: string }>();
  const teachersMap = new Map<string, { id: string; name: string; url: string; category: string }>();
  const roomsMap = new Map<string, { id: string; name: string; url: string; category: string }>();

  $('a[href]').each((_, el) => {
    const rawHref = ($(el).attr('href') || '').trim();
    const text = $(el).text().trim();
    if (!rawHref || !text || rawHref.startsWith('javascript:') || rawHref.startsWith('#')) return;
    const clean = rawHref.split('?')[0].split('#')[0].toLowerCase();
    const absUrl = resolveUrl(baseUrl, rawHref);
    const id = absUrl.split('/').pop() || absUrl;

    if (/(^|\/)o\d+[^/]*\.html?$/.test(clean) || clean.includes('plany/o')) {
      if (!classesMap.has(absUrl)) classesMap.set(absUrl, { id, name: text, url: absUrl });
    } else if (/(^|\/)n\d+[^/]*\.html?$/.test(clean) || clean.includes('plany/n')) {
      if (!teachersMap.has(absUrl)) teachersMap.set(absUrl, { id, name: text, url: absUrl, category: 'TEACHER' });
    } else if (/(^|\/)s\d+[^/]*\.html?$/.test(clean) || clean.includes('plany/s')) {
      if (!roomsMap.has(absUrl)) roomsMap.set(absUrl, { id, name: text, url: absUrl, category: 'ROOM' });
    }
  });

  const classes = Array.from(classesMap.values()).sort((a, b) => {
    const na = parseInt(a.name, 10) || 99;
    const nb = parseInt(b.name, 10) || 99;
    return na !== nb ? na - nb : a.name.localeCompare(b.name, 'pl');
  });
  const teachers = Array.from(teachersMap.values()).sort((a, b) => a.name.localeCompare(b.name, 'pl'));
  const rooms = Array.from(roomsMap.values()).sort((a, b) => a.name.localeCompare(b.name, 'pl'));
  return { classes, teachers, rooms };
}

function parseTimetableHtml(html: string, name: string, url: string, category: string) {
  const $ = cheerio.load(html);
  const table = $('table.tabela').first().length ? $('table.tabela').first() : $('table').last();
  const rows = table.find('tr').toArray();
  const lessonsByDay: Array<Array<{
    period: number;
    timeRange: string;
    subject: string;
    teacher: string;
    room: string;
    classGroupLabel: string;
    groupTag: string | null;
    rawText: string;
  }>> = [[], [], [], [], []];

  if (rows.length > 1) {
    type GridSlot = { el: cheerio.Cheerio<any>; cont: boolean };
    const grid: Array<Array<GridSlot | null>> = rows.map(() => []);

    rows.forEach((tr, rIdx) => {
      const cells = $(tr).children('th, td').toArray();
      let cIdx = 0;
      for (const cell of cells) {
        while (cIdx < grid[rIdx].length && grid[rIdx][cIdx] !== null) cIdx++;
        const $cell = $(cell);
        const rowspan = Math.max(1, parseInt($cell.attr('rowspan') || '1', 10) || 1);
        const colspan = Math.max(1, parseInt($cell.attr('colspan') || '1', 10) || 1);
        for (let dr = 0; dr < rowspan; dr++) {
          const targetRow = rIdx + dr;
          if (targetRow >= rows.length) break;
          while (grid[targetRow].length < cIdx + colspan) grid[targetRow].push(null);
          for (let dc = 0; dc < colspan; dc++) {
            grid[targetRow][cIdx + dc] = { el: $cell, cont: dc > 0 };
          }
        }
        cIdx += colspan;
      }
    });

    const headerLen = grid[0]?.length ?? 0;
    const dayColStart = headerLen >= 7 ? 2 : headerLen === 6 ? 1 : 2;

    for (let rIdx = 1; rIdx < grid.length; rIdx++) {
      const row = grid[rIdx];
      if (row.length <= dayColStart) continue;
      const periodText = (row[0]?.el.text() || '').trim();
      const periodNum = parseInt(periodText.replace(/\D/g, ''), 10) || rIdx - 1;
      const timeRange = dayColStart > 1 ? (row[1]?.el.text() || '').trim() : '';

      for (let dIdx = 0; dIdx < 5; dIdx++) {
        const slot = row[dayColStart + dIdx];
        if (!slot || slot.cont) continue;
        const cellHtml = slot.el.html() || '';
        const cellText = slot.el.text().replace(/\u00A0/g, ' ').trim();
        if (!cellText || cellText === '-' || cellText === '—') continue;

        const segments = cellHtml
          .replace(/<br\s*\/?>/gi, '\n')
          .replace(/<hr\s*\/?>/gi, '\n')
          .split('\n')
          .map((s) => s.trim())
          .filter(Boolean);

        for (const segHtml of segments.length ? segments : [cellHtml]) {
          const $seg = cheerio.load(segHtml);
          const segText = $seg.text().replace(/\u00A0/g, ' ').trim();
          if (!segText || segText === '-' || segText === '—') continue;

          const teachers = Array.from(new Set($seg('a.n, span.n, .n').map((_, e) => $seg(e).text().trim()).get().filter(Boolean))).join(', ');
          const rooms = Array.from(new Set($seg('a.s, span.s, .s').map((_, e) => $seg(e).text().trim()).get().filter(Boolean))).join(', ');
          const classes = Array.from(new Set($seg('a.o, span.o, .o').map((_, e) => $seg(e).text().trim()).get().filter(Boolean))).join(', ');
          const subjects = $seg('span.p, .p').map((_, e) => $seg(e).text().trim()).get().filter(Boolean);
          const subject = subjects.length ? subjects.join(' ') : segText;

          lessonsByDay[dIdx].push({
            period: periodNum,
            timeRange,
            subject,
            teacher: teachers,
            room: rooms,
            classGroupLabel: classes,
            groupTag: detectGroupTag(`${subject} ${classes} ${segText}`),
            rawText: segText,
          });
        }
      }
    }
  }

  return {
    className: name,
    classUrl: url,
    category,
    fetchedAtMillis: Date.now(),
    days: DEFAULT_DAYS.map((dayName, idx) => ({
      dayIndex: idx,
      dayName,
      lessons: lessonsByDay[idx].sort((a, b) => a.period - b.period),
    })),
  };
}

function parseSubstitutionsHtml(html: string, sourceUrl: string) {
  const $ = cheerio.load(html);
  $('script, style, noscript, svg').remove();

  const dateHeading = $('.naglowek, h1, h2, h3').first().text().replace(/\s+/g, ' ').trim();
  const announcements: string[] = [];
  const notes: string[] = [];
  const items: Array<{
    id: string;
    dateLabel: string;
    className: string;
    period: string;
    timeRange: string;
    absentTeacher: string;
    subject: string;
    substituteTeacher: string;
    room: string;
    note: string;
    groupTag: string | null;
    isCancellation: boolean;
  }> = [];

  $('fieldset').each((_, fsEl) => {
    const $fs = $(fsEl).clone();
    const legend = $fs.find('legend').text().toLowerCase();
    $fs.find('legend').remove();
    const lines = ($fs.html() || '')
      .replace(/<br\s*\/?>/gi, '\n')
      .split('\n')
      .map((line) => cheerio.load(line).text().trim())
      .filter(Boolean);
    if (legend.includes('uwag')) notes.push(...lines);
    else announcements.push(...lines);
  });

  $('table').each((_, tbl) => {
    const rows = $(tbl).find('tr').toArray();
    let colPeriod = -1;
    let colAbsent = -1;
    let colClass = -1;
    let colSubject = -1;
    let colRoom = -1;
    let colSub = -1;
    let colNote = -1;
    let currentDate = dateHeading;
    let startRow = 0;

    for (let i = 0; i < rows.length; i++) {
      const ths = $(rows[i]).children('th').toArray();
      const texts = ths.map((th) => $(th).text().trim());
      if (texts.length === 1 && texts[0]) {
        if (texts[0].toLowerCase().includes('dzień:') || /\d{2}\.\d{2}\.\d{4}|\d{4}-\d{2}-\d{2}/.test(texts[0])) {
          currentDate = texts[0].replace(/Dzień:/i, '').trim();
        }
        continue;
      }
      if (ths.length >= 3) {
        texts.forEach((rawH, idx) => {
          const h = foldPolish(rawH.toLowerCase());
          if (h.includes('lekc') || h.includes('godz') || h === 'nr') colPeriod = idx;
          else if (h.includes('nieobec') || h.includes('nauczyciel') || h.includes('wakat')) colAbsent = idx;
          else if (h.includes('oddz') || h.includes('klas')) colClass = idx;
          else if (h.includes('przedm') || h.includes('zajec')) colSubject = idx;
          else if (h.includes('sal')) colRoom = idx;
          else if (h.includes('zastepc') || h.includes('zastepuj') || h.includes('dyzuruj')) colSub = idx;
          else if (h.includes('uwag') || h.includes('opis')) colNote = idx;
        });
        startRow = i + 1;
        break;
      }
    }

    for (let i = startRow; i < rows.length; i++) {
      const tds = $(rows[i]).children('td').toArray();
      if (!tds.length) continue;
      const vals = tds.map((td) => $(td).text().trim());
      if (vals.every((v) => !v)) continue;

      const periodRaw = colPeriod >= 0 ? vals[colPeriod] || '' : vals[0] || '';
      const absent = colAbsent >= 0 ? vals[colAbsent] || '' : '';
      const className = colClass >= 0 ? vals[colClass] || '' : '';
      const subject = colSubject >= 0 ? vals[colSubject] || '' : '';
      const room = colRoom >= 0 ? vals[colRoom] || '' : '';
      const sub = colSub >= 0 ? vals[colSub] || '' : '';
      const note = colNote >= 0 ? vals[colNote] || '' : '';

      let periodOnly = periodRaw;
      let timeRange = '';
      const commaIdx = periodRaw.indexOf(',');
      if (commaIdx >= 0) {
        periodOnly = periodRaw.slice(0, commaIdx).trim();
        timeRange = periodRaw.slice(commaIdx + 1).trim();
      }

      const combined = `${sub} ${note} ${subject}`;
      items.push({
        id: `${currentDate}_${className}_${periodOnly}_${items.length}`,
        dateLabel: currentDate,
        className,
        period: periodOnly,
        timeRange,
        absentTeacher: absent,
        subject,
        substituteTeacher: sub,
        room,
        note,
        groupTag: detectGroupTag(`${className} ${subject} ${note}`),
        isCancellation: isCancellationText(combined),
      });
    }
  });

  return {
    dateHeading,
    announcements: Array.from(new Set(announcements)),
    notes: Array.from(new Set(notes)),
    items,
    fetchedAtMillis: Date.now(),
    sourceUrl,
  };
}

function walkIosFiles(dirPath: string, rootDir: string, out: Array<{ path: string; size: number; isBinary: boolean; content?: string }> = []) {
  if (!fs.existsSync(dirPath)) return out;
  const entries = fs.readdirSync(dirPath, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const full = path.join(dirPath, entry.name);
    const rel = path.relative(rootDir, full).replace(/\\/g, '/');
    if (entry.isDirectory()) {
      walkIosFiles(full, rootDir, out);
    } else {
      const stat = fs.statSync(full);
      const isBinary = /\.(png|jpg|jpeg|ico|icns|ttf|otf)$/i.test(entry.name);
      out.push({
        path: rel,
        size: stat.size,
        isBinary,
        content: isBinary ? undefined : fs.readFileSync(full, 'utf8'),
      });
    }
  }
  return out;
}

async function startServer() {
  const app = express();
  app.use(express.json({ limit: '2mb' }));

  app.get('/api/zsme/catalog', async (req, res) => {
    try {
      const base = typeof req.query.baseUrl === 'string' && req.query.baseUrl.trim() ? req.query.baseUrl.trim() : PLAN_BASE_URL;
      const listaUrl = resolveUrl(base, 'lista.html');
      const { finalUrl, html } = await fetchText(listaUrl);
      const catalog = parseCatalog(html, finalUrl);
      if (!catalog.classes.length && !catalog.teachers.length && !catalog.rooms.length) {
        const root = await fetchText(base);
        res.json(parseCatalog(root.html, root.finalUrl));
        return;
      }
      res.json(catalog);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Błąd pobierania katalogu';
      res.status(502).json({ error: message });
    }
  });

  app.get('/api/zsme/timetable', async (req, res) => {
    try {
      const targetUrl = typeof req.query.url === 'string' ? req.query.url.trim() : '';
      const name = typeof req.query.name === 'string' ? req.query.name.trim() : 'Plan';
      const category = typeof req.query.category === 'string' ? req.query.category.trim() : 'CLASS';
      if (!targetUrl || !/^https?:\/\//i.test(targetUrl)) {
        res.status(400).json({ error: 'Wymagany poprawny parametr url' });
        return;
      }
      const { finalUrl, html } = await fetchText(targetUrl);
      res.json(parseTimetableHtml(html, name, finalUrl, category));
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Błąd pobierania planu lekcji';
      res.status(502).json({ error: message });
    }
  });

  app.get('/api/zsme/substitutions', async (req, res) => {
    try {
      const targetUrl = typeof req.query.url === 'string' && req.query.url.trim() ? req.query.url.trim() : SUBSTITUTIONS_URL;
      const { finalUrl, html } = await fetchText(targetUrl);
      res.json(parseSubstitutionsHtml(html, finalUrl));
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Błąd pobierania zastępstw';
      res.status(502).json({ error: message });
    }
  });

  app.get('/api/ios-files', (_req, res) => {
    const iosRoot = path.join(__dirname, 'ios-app');
    const files = walkIosFiles(iosRoot, iosRoot);
    res.json({ root: 'ios-app', files });
  });

  app.get('/api/export-ios-zip', async (_req, res) => {
    try {
      const iosRoot = path.join(__dirname, 'ios-app');
      const zip = new JSZip();

      const addFolderToZip = (dir: string) => {
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
          const full = path.join(dir, entry.name);
          const rel = path.relative(iosRoot, full).replace(/\\/g, '/');
          if (entry.isDirectory()) {
            addFolderToZip(full);
          } else {
            zip.file(rel, fs.readFileSync(full));
          }
        }
      };

      addFolderToZip(iosRoot);
      const buffer = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', 'attachment; filename="ZSME-Assistant-iOS.zip"');
      res.send(buffer);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Nie udało się spakować projektu iOS';
      res.status(500).json({ error: message });
    }
  });

  app.post('/api/export-ics', (req, res) => {
    const body = req.body as {
      className?: string;
      days?: Array<{ dayIndex: number; lessons: Array<{ period: number; timeRange: string; subject: string; teacher: string; room: string }> }>;
    };
    const className = (body?.className || 'ZSME').replace(/[\r\n]/g, '');
    const days = Array.isArray(body?.days) ? body.days : [];

    const now = new Date();
    const dow = now.getDay(); // 0=Sun..6=Sat
    const diffToMon = dow === 0 ? -6 : 1 - dow;
    const monday = new Date(now);
    monday.setDate(now.getDate() + diffToMon);

    const pad = (n: number) => String(n).padStart(2, '0');
    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//ZSME Assistant//iOS//PL',
      `X-WR-CALNAME:Plan lekcji — ${className}`,
      'X-WR-TIMEZONE:Europe/Warsaw',
    ];

    for (const day of days) {
      if (day.dayIndex < 0 || day.dayIndex > 4) continue;
      const d = new Date(monday);
      d.setDate(monday.getDate() + day.dayIndex);
      const yyyymmdd = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;

      for (const lesson of day.lessons) {
        const match = /(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})/.exec(lesson.timeRange || '');
        const sh = match ? pad(parseInt(match[1], 10)) : '08';
        const sm = match ? pad(parseInt(match[2], 10)) : '00';
        const eh = match ? pad(parseInt(match[3], 10)) : '08';
        const em = match ? pad(parseInt(match[4], 10)) : '45';

        lines.push('BEGIN:VEVENT');
        lines.push(`UID:${yyyymmdd}-${day.dayIndex}-${lesson.period}-${Math.random().toString(36).slice(2, 8)}@zsme.pl`);
        lines.push(`DTSTART;TZID=Europe/Warsaw:${yyyymmdd}T${sh}${sm}00`);
        lines.push(`DTEND;TZID=Europe/Warsaw:${yyyymmdd}T${eh}${em}00`);
        lines.push('RRULE:FREQ=WEEKLY;COUNT=16');
        lines.push(`SUMMARY:${lesson.subject || `Lekcja ${lesson.period}`}`);
        if (lesson.room) lines.push(`LOCATION:Sala ${lesson.room}`);
        if (lesson.teacher) lines.push(`DESCRIPTION:Nauczyciel: ${lesson.teacher}`);
        lines.push('END:VEVENT');
      }
    }
    lines.push('END:VCALENDAR');

    res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="plan-${className.replace(/[^a-zA-Z0-9_-]/g, '')}.ics"`);
    res.send(lines.join('\r\n'));
  });

  if (process.env.NODE_ENV !== 'production') {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(__dirname, 'dist');
    app.use(express.static(distPath));
    app.get('*', (_req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  const PORT = 3000;
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`ZSME Assistant iOS Studio running at http://0.0.0.0:${PORT}`);
  });
}

startServer();
