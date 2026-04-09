import 'dart:math' as math;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Zendenta / Notion-style data table — white surface, grey header, row hover.
class PillrDataTable extends StatelessWidget {
  const PillrDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSelectAll,
    this.minWidth = 720,
  });

  final List<DataColumn2> columns;
  final List<DataRow> rows;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(bool? selected)? onSelectAll;
  final double minWidth;

  static const double _headingRowHeight = 48;
  static const double _dataRowHeight = 56;

  @override
  Widget build(BuildContext context) {
    final styledColumns = columns
        .map(
          (c) => DataColumn2(
            label: DefaultTextStyle.merge(
              style: AppTypography.tableHeader,
              child: c.label,
            ),
            tooltip: c.tooltip,
            numeric: c.numeric,
            fixedWidth: c.fixedWidth,
            size: c.size,
            onSort: c.onSort,
          ),
        )
        .toList();

    // data_table_2 uses a Column with Flexible children; that requires a bounded
    // max height. Placing DataTable2 inside SingleChildScrollView gives unbounded
    // height and throws on web ("RenderFlex children have non-zero flex...").
    final boundedHeight = _headingRowHeight + _dataRowHeight * rows.length + 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final effectiveWidth = maxW.isFinite
            ? math.max(minWidth, maxW)
            : minWidth;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.gray200),
            boxShadow: AppTheme.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: boundedHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: effectiveWidth,
                height: boundedHeight,
                child: DataTable2(
                  columnSpacing: AppSpacing.md,
                  horizontalMargin: AppSpacing.md,
                  minWidth: effectiveWidth,
                  headingRowHeight: _headingRowHeight,
                  dataRowHeight: _dataRowHeight,
                  headingRowDecoration: const BoxDecoration(
                    color: AppColors.gray50,
                    border: Border(
                      bottom: BorderSide(color: AppColors.gray200),
                    ),
                  ),
                  decoration: const BoxDecoration(),
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  onSelectAll: onSelectAll,
                  columns: styledColumns,
                  rows: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
