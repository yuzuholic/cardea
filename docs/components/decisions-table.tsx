'use client';

import { useState, type ReactNode } from 'react';

// order here is the order a status sort uses
const STATUS = {
  Adopted: 'border-fd-success/40 bg-fd-success/10 [--dot:var(--color-fd-success)]',
  Deferred: 'border-fd-warning/40 bg-fd-warning/10 [--dot:var(--color-fd-warning)]',
  Replaced: 'border-fd-border bg-fd-muted [--dot:var(--color-fd-muted-foreground)]',
  Removed: 'border-fd-border bg-fd-muted [--dot:var(--color-fd-muted-foreground)]',
  Rejected: 'border-fd-error/40 bg-fd-error/10 [--dot:var(--color-fd-error)]',
} as const;

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
    <div className="not-prose overflow-x-auto rounded-xl border bg-fd-card text-sm">
      <table className="w-full border-collapse">
        <thead>
          <tr className="border-b text-left">
            {COLUMNS.map(({ key, label }) => {
              const active = sort?.key === key;
              return (
                <th key={key} aria-sort={active ? (sort.asc ? 'ascending' : 'descending') : 'none'} className="p-0 font-medium">
                  <button
                    type="button"
                    onClick={() => setSort({ key, asc: active ? !sort.asc : true })}
                    className="inline-flex w-full items-center gap-1 whitespace-nowrap px-3 py-2.5 hover:text-fd-primary"
                  >
                    {label}
                    <span aria-hidden className={active ? 'text-fd-primary' : 'text-fd-muted-foreground/50'}>
                      {active && !sort.asc ? '↓' : '↑'}
                    </span>
                  </button>
                </th>
              );
            })}
            <th className="hidden px-3 py-2.5 font-medium sm:table-cell">Why</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.title} className="border-b align-top last:border-b-0">
              <td className="px-3 py-3">
                <p className="font-medium">{row.title}</p>
                {/* phones have no room for a fourth column, so the reason sits under the name */}
                <div className={`mt-1 text-fd-muted-foreground sm:hidden ${WHY}`}>{row.why}</div>
              </td>
              <td className="whitespace-nowrap px-3 py-3 text-fd-muted-foreground">{row.area}</td>
              <td className="px-3 py-3">
                <span className={`inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-xs font-medium ${STATUS[row.status]}`}>
                  <span aria-hidden className="size-1.5 rounded-full bg-(--dot)" />
                  {row.status}
                </span>
              </td>
              <td className={`hidden min-w-64 px-3 py-3 text-fd-muted-foreground sm:table-cell ${WHY}`}>
                {row.why}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
