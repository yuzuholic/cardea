'use client';

import { useState, type ReactNode } from 'react';

// order here is the order a status sort uses
const STATUS = {
  Adopted: 'border-fd-success/40 bg-fd-success/10',
  Deferred: 'border-fd-warning/40 bg-fd-warning/10',
  Replaced: 'border-fd-border bg-fd-muted',
  Removed: 'border-fd-border bg-fd-muted',
  Rejected: 'border-fd-error/40 bg-fd-error/10',
} as const;

// opaque so rows scroll under it; top clears the sticky bar and tab row
const HEAD =
  'sticky top-[6.75rem] md:top-[9.5rem] z-10 border-b border-fd-border bg-[color-mix(in_oklab,var(--color-fd-card),var(--color-fd-foreground)_6%)] first:rounded-tl-xl last:rounded-tr-xl';
const ORDER = Object.keys(STATUS);
const WHY = '[&_code]:rounded [&_code]:bg-fd-muted [&_code]:px-1 [&_code]:text-[0.8125rem]';

export type Decision = { title: string; area: string; status: keyof typeof STATUS; why: ReactNode };
type Key = 'title' | 'area' | 'status';
const COLUMNS: { key: Key; label: string }[] = [
  { key: 'title', label: 'Decision' },
  { key: 'area', label: 'Area' },
  { key: 'status', label: 'Status' },
];

export function DecisionsTable({ decisions }: { decisions: Decision[] }) {
  // null keeps the order the page lists them in
  const [sort, setSort] = useState<{ key: Key; asc: boolean } | null>(null);

  const rows = sort
    ? [...decisions].sort((a, b) => {
        const order =
          sort.key === 'status'
            ? ORDER.indexOf(a.status) - ORDER.indexOf(b.status)
            : a[sort.key].localeCompare(b[sort.key]);
        return sort.asc ? order : -order;
      })
    : decisions;

  return (
    <>
    <div className="not-prose mb-3 flex items-center gap-2 text-sm sm:hidden">
      <label htmlFor="decisions-sort" className="text-fd-muted-foreground">
        Sort by
      </label>
      <select
        id="decisions-sort"
        value={sort?.key ?? ''}
        onChange={(e) => setSort({ key: e.target.value as Key, asc: sort?.asc ?? true })}
        className="rounded-lg bg-fd-card px-3 py-1.5 text-fd-foreground"
      >
        <option value="" disabled>
          Page order
        </option>
        {COLUMNS.map(({ key, label }) => (
          <option key={key} value={key}>
            {label}
          </option>
        ))}
      </select>
      <button
        type="button"
        disabled={!sort}
        aria-label={sort?.asc === false ? 'Descending, switch to ascending' : 'Ascending, switch to descending'}
        onClick={() => sort && setSort({ ...sort, asc: !sort.asc })}
        className="cursor-pointer rounded-lg bg-fd-card px-3 py-1.5 disabled:opacity-40"
      >
        {sort?.asc === false ? '↓' : '↑'}
      </button>
    </div>
    <ul className="not-prose space-y-3 text-sm sm:hidden">
      {rows.map((row) => (
        <li key={row.title} className="rounded-xl bg-fd-card p-4">
          <p className="font-medium">{row.title}</p>
          <p className="mt-1.5 flex items-center gap-2">
            <span className="text-fd-muted-foreground">{row.area}</span>
            <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium ${STATUS[row.status]}`}>
              {row.status}
            </span>
          </p>
          <div className={`mt-2 text-fd-muted-foreground ${WHY}`}>{row.why}</div>
        </li>
      ))}
    </ul>
    <div className="not-prose hidden rounded-xl bg-fd-card text-sm sm:block">
      <table className="w-full border-collapse">
        <thead>
          <tr className="text-left">
            {COLUMNS.map(({ key, label }) => {
              const active = sort?.key === key;
              return (
                <th key={key} aria-sort={active ? (sort.asc ? 'ascending' : 'descending') : 'none'} className={`${HEAD} min-w-0 p-0 font-medium ${key === 'title' ? 'min-w-56' : ''}`}>
                  <button
                    type="button"
                    data-ring-fill
                    onClick={() => setSort({ key, asc: active ? !sort.asc : true })}
                    className="group inline-flex w-full cursor-pointer items-center gap-1 whitespace-nowrap px-3 py-2.5 hover:text-fd-primary"
                  >
                    {label}
                    <span
                      aria-hidden
                      className={active ? 'text-fd-foreground' : 'text-fd-muted-foreground opacity-40 group-hover:text-fd-primary group-hover:opacity-100 group-focus-visible:opacity-100'}
                    >
                      {active ? (sort.asc ? '↑' : '↓') : '↕'}
                    </span>
                  </button>
                </th>
              );
            })}
            <th className={`${HEAD} px-3 py-2.5 font-medium`}>Why</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.title} id={row.title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')} className="scroll-mt-52 border-b border-fd-border align-top last:border-b-0">
              <td className="px-3 py-3">
                <p className="font-medium">{row.title}</p>
              </td>
              <td className="whitespace-nowrap px-3 py-3 text-fd-muted-foreground">{row.area}</td>
              <td className="px-3 py-3">
                <span className={`inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-xs font-medium ${STATUS[row.status]}`}>
                  {row.status}
                </span>
              </td>
              <td className={`min-w-64 px-3 py-3 text-fd-muted-foreground ${WHY}`}>
                {row.why}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
    </>
  );
}
