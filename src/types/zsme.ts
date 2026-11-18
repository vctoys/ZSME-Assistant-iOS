export type UserRole = 'STUDENT' | 'TEACHER';
export type StudentGroup = 'ALL' | 'GROUP_1' | 'GROUP_2';
export type TimetableCategory = 'CLASS' | 'TEACHER' | 'ROOM';

export interface SchoolClass {
  id: string;
  name: string;
  url: string;
}

export interface TimetableTarget {
  id: string;
  name: string;
  url: string;
  category: TimetableCategory;
}

export interface TimetableCatalog {
  classes: SchoolClass[];
  teachers: TimetableTarget[];
  rooms: TimetableTarget[];
}

export interface LessonEntry {
  period: number;
  timeRange: string;
  subject: string;
  teacher: string;
  room: string;
  classGroupLabel: string;
  groupTag: string | null;
  rawText: string;
}

export interface DaySchedule {
  dayIndex: number;
  dayName: string;
  lessons: LessonEntry[];
}

export interface ClassTimetable {
  className: string;
  classUrl: string;
  category: TimetableCategory;
  fetchedAtMillis: number;
  days: DaySchedule[];
}

export interface SubstitutionItem {
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
}

export interface SubstitutionsSnapshot {
  dateHeading: string;
  announcements: string[];
  notes: string[];
  items: SubstitutionItem[];
  fetchedAtMillis: number;
  sourceUrl: string;
}

export interface IosProjectFile {
  path: string;
  size: number;
  isBinary: boolean;
  content?: string;
}
