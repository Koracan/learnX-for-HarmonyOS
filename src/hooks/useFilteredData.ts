import { useMemo } from 'react';
import type { Assignment, Notice } from 'data/types/state';

function useFilteredData<T extends Notice | Assignment>({
  data,
  fav,
  archived,
  hidden,
}: {
  data: T[];
  fav: string[];
  archived: string[];
  hidden: string[];
}) {
  const _all = useMemo(
    () =>
      data.filter(
        i => !archived.includes(i.id) && !hidden.includes(i.courseId),
      ),
    [data, archived, hidden],
  );

  const _fav = useMemo(() => _all.filter(i => fav.includes(i.id)), [_all, fav]);

  const _archived = useMemo(
    () => data.filter(i => archived.includes(i.id)),
    [data, archived],
  );

  const _unfinished = useMemo(
    () => _all.filter(i => !(i as Assignment).submitted),
    [_all],
  );

  const _finished = useMemo(
    () => _all.filter(i => (i as Assignment).submitted),
    [_all],
  );

  return {
    all: _all,
    fav: _fav,
    archived: _archived,
    unfinished: _unfinished,
    finished: _finished,
  };
}

export default useFilteredData;
