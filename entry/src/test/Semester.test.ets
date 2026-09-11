/*
 * domain.Semester 单测：解析 / 校验 / 比较 / 排序。
 * 排序语义与参考实现一致（reference/learnOH-old/src/data/actions/semesters.ts 用 sort().reverse()）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  Semester, SemesterSeason, SemesterParts, parseSemesterId, isValidSemesterId,
  compareSemesterIds, sortSemesterIds, latestSemesterId, seasonOfTerm, academicYearOf
} from '../main/ets/domain/model/Semester';

function throwsOn(raw: string): boolean {
  try {
    Semester.parse(raw);
    return false;
  } catch (error) {
    return true;
  }
}

export default function semesterTest() {
  describe('domain.Semester', () => {
    it('parses YYYY-YYYY-N', 0, () => {
      const semester: Semester = Semester.parse('2025-2026-2');
      expect(semester.startYear).assertEqual(2025);
      expect(semester.endYear).assertEqual(2026);
      expect(semester.term).assertEqual(2);
      expect(semester.id).assertEqual('2025-2026-2');
      expect(semester.academicYear).assertEqual('2025-2026');
      expect(semester.toString()).assertEqual('2025-2026-2');
      expect(Semester.isId('2025-2026-2')).assertTrue();
    });

    it('maps term to season like the reference implementation', 0, () => {
      expect(seasonOfTerm(1)).assertEqual(SemesterSeason.FALL);
      expect(seasonOfTerm(2)).assertEqual(SemesterSeason.SPRING);
      expect(seasonOfTerm(3)).assertEqual(SemesterSeason.SUMMER);
      expect(seasonOfTerm(9)).assertEqual(SemesterSeason.SUMMER);
      expect(Semester.parse('2025-2026-1').season).assertEqual(SemesterSeason.FALL);
      expect(Semester.parse('2025-2026-2').season).assertEqual(SemesterSeason.SPRING);
    });

    it('rejects malformed ids', 0, () => {
      const bad: string[] = ['', '   ', '2025-2026', '2025-2027-1', '2025-2026-0', 'abc', '25-26-1', '2025-2026-1x', '2025/2026/1'];
      for (let i = 0; i < bad.length; i++) {
        expect(throwsOn(bad[i])).assertTrue();
        expect(isValidSemesterId(bad[i])).assertFalse();
        expect(Semester.tryParse(bad[i]) === null).assertTrue();
      }
      expect(isValidSemesterId('2025-2026-1')).assertTrue();
    });

    it('trims surrounding whitespace', 0, () => {
      expect(Semester.parse('  2025-2026-1  ').id).assertEqual('2025-2026-1');
      expect(isValidSemesterId(' 2025-2026-1 ')).assertTrue();
    });

    it('orders semesters chronologically', 0, () => {
      const autumn: Semester = Semester.parse('2024-2025-2');
      const spring: Semester = Semester.parse('2025-2026-1');
      const next: Semester = Semester.parse('2025-2026-2');
      expect(autumn.isBefore(spring)).assertTrue();
      expect(spring.isAfter(autumn)).assertTrue();
      expect(spring.compareTo(spring)).assertEqual(0);
      expect(next.isAfter(spring)).assertTrue();
      expect(spring.equals(Semester.parse('2025-2026-1'))).assertTrue();
      expect(spring.equals(next)).assertFalse();
      expect(autumn.compareTo(spring) < 0).assertTrue();
    });

    it('compareSemesterIds agrees with lexicographic order on well-formed ids', 0, () => {
      const ids: string[] = ['2019-2020-1', '2019-2020-2', '2020-2021-1', '2020-2021-2', '2021-2022-1'];
      for (let i = 0; i + 1 < ids.length; i++) {
        expect(compareSemesterIds(ids[i], ids[i + 1]) < 0).assertTrue();
        expect(compareSemesterIds(ids[i + 1], ids[i]) > 0).assertTrue();
      }
      expect(compareSemesterIds(ids[0], ids[0])).assertEqual(0);
    });

    it('sorts desc exactly like the reference implementation (sort().reverse())', 0, () => {
      const ids: string[] = ['2020-2021-1', '2019-2020-2', '2021-2022-1', '2019-2020-1', '2020-2021-2'];
      const reference: string[] = ids.slice().sort().reverse();
      const sorted: string[] = sortSemesterIds(ids, 'desc');
      expect(sorted.length).assertEqual(reference.length);
      for (let i = 0; i < reference.length; i++) {
        expect(sorted[i]).assertEqual(reference[i]);
      }
      expect(sortSemesterIds(ids, 'asc')[0]).assertEqual('2019-2020-1');
      expect(sortSemesterIds(ids).length).assertEqual(ids.length);
      expect(ids[0]).assertEqual('2020-2021-1');
    });

    it('picks the latest id and parks invalid ids last', 0, () => {
      expect(latestSemesterId(['2020-2021-1', '2021-2022-2', '2019-2020-1'])).assertEqual('2021-2022-2');
      expect(latestSemesterId(['junk', '2021-2022-2'])).assertEqual('2021-2022-2');
      expect(latestSemesterId([]) === null).assertTrue();
      expect(latestSemesterId(['junk']) === null).assertTrue();
      expect(compareSemesterIds('junk', '2021-2022-2') > 0).assertTrue();
      expect(compareSemesterIds('2021-2022-2', 'junk') < 0).assertTrue();
      expect(compareSemesterIds('junk', 'junk')).assertEqual(0);
    });

    it('exposes parsed parts and academic year text', 0, () => {
      const parts: SemesterParts = parseSemesterId('2025-2026-3');
      expect(parts.startYear).assertEqual(2025);
      expect(parts.endYear).assertEqual(2026);
      expect(parts.term).assertEqual(3);
      expect(academicYearOf(2025, 2026)).assertEqual('2025-2026');
    });
  });
}
