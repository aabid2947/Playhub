"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  type ColumnDef,
  type SortingState,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
} from "@tanstack/react-table";
import { ArrowUpDown, ChevronLeft, ChevronRight, Download } from "lucide-react";
import { Table, THead, TBody, TR, TH, TD } from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { toCsv, type CsvColumn } from "@/lib/csv";
import { downloadText } from "@/lib/download";

export type { ColumnDef };

export type ExportConfig<TData> = {
  filename: string;
  columns: CsvColumn<TData>[];
};

export function DataTable<TData>({
  columns,
  data,
  searchPlaceholder = "Search…",
  rowHref,
  initialSorting = [],
  toolbar,
  exportConfig,
}: {
  columns: ColumnDef<TData, unknown>[];
  data: TData[];
  searchPlaceholder?: string;
  rowHref?: (row: TData) => string;
  initialSorting?: SortingState;
  toolbar?: React.ReactNode;
  exportConfig?: ExportConfig<TData>;
}) {
  const router = useRouter();
  const [sorting, setSorting] = useState<SortingState>(initialSorting);
  const [globalFilter, setGlobalFilter] = useState("");

  const table = useReactTable({
    data,
    columns,
    state: { sorting, globalFilter },
    onSortingChange: setSorting,
    onGlobalFilterChange: setGlobalFilter,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: 25 } },
  });

  const rows = table.getRowModel().rows;

  function exportCsv() {
    if (!exportConfig) return;
    // Export the rows currently matching the search filter (all pages).
    const filtered = table
      .getFilteredRowModel()
      .rows.map((r) => r.original as TData);
    downloadText(exportConfig.filename, toCsv(filtered, exportConfig.columns));
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-3">
        <Input
          value={globalFilter}
          onChange={(e) => setGlobalFilter(e.target.value)}
          placeholder={searchPlaceholder}
          className="max-w-xs"
        />
        <div className="flex items-center gap-2">
          {toolbar}
          {exportConfig && (
            <Button variant="outline" size="sm" onClick={exportCsv}>
              <Download size={14} /> Export CSV
            </Button>
          )}
        </div>
      </div>

      <div className="rounded-[var(--radius)] border border-[var(--color-border)] bg-[var(--color-surface)]">
        <Table>
          <THead>
            {table.getHeaderGroups().map((hg) => (
              <tr key={hg.id}>
                {hg.headers.map((header) => {
                  const canSort = header.column.getCanSort();
                  return (
                    <TH key={header.id}>
                      {header.isPlaceholder ? null : (
                        <button
                          type="button"
                          disabled={!canSort}
                          onClick={header.column.getToggleSortingHandler()}
                          className={cn(
                            "inline-flex items-center gap-1",
                            canSort && "cursor-pointer hover:text-[var(--color-fg)]",
                          )}
                        >
                          {flexRender(
                            header.column.columnDef.header,
                            header.getContext(),
                          )}
                          {canSort && <ArrowUpDown size={12} />}
                        </button>
                      )}
                    </TH>
                  );
                })}
              </tr>
            ))}
          </THead>
          <TBody>
            {rows.length === 0 ? (
              <TR>
                <TD
                  colSpan={columns.length}
                  className="py-10 text-center text-[var(--color-muted)]"
                >
                  No rows.
                </TD>
              </TR>
            ) : (
              rows.map((row) => (
                <TR
                  key={row.id}
                  onClick={
                    rowHref ? () => router.push(rowHref(row.original)) : undefined
                  }
                  className={rowHref ? "cursor-pointer" : undefined}
                >
                  {row.getVisibleCells().map((cell) => (
                    <TD key={cell.id}>
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TD>
                  ))}
                </TR>
              ))
            )}
          </TBody>
        </Table>
      </div>

      <div className="flex items-center justify-between text-xs text-[var(--color-muted)]">
        <span>
          {table.getFilteredRowModel().rows.length} row
          {table.getFilteredRowModel().rows.length === 1 ? "" : "s"}
        </span>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="icon"
            onClick={() => table.previousPage()}
            disabled={!table.getCanPreviousPage()}
            aria-label="Previous page"
          >
            <ChevronLeft size={16} />
          </Button>
          <span>
            Page {table.getState().pagination.pageIndex + 1} of{" "}
            {table.getPageCount() || 1}
          </span>
          <Button
            variant="outline"
            size="icon"
            onClick={() => table.nextPage()}
            disabled={!table.getCanNextPage()}
            aria-label="Next page"
          >
            <ChevronRight size={16} />
          </Button>
        </div>
      </div>
    </div>
  );
}
