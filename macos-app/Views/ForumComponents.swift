import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

struct CommentBlock: View {
    let comment: CommentPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.userName ?? comment.brokerUserId ?? "未知用户")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(comment.createdAt ?? "未知时间")
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Text("赞 \(comment.likeCount ?? 0)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
            }

            Text(comment.content ?? "无内容")
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !comment.children.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(comment.children) { reply in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(AppPalette.brand.opacity(0.28))
                                .frame(width: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reply.userName ?? reply.brokerUserId ?? "未知回复")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppPalette.ink)
                                Text(reply.content ?? "无内容")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.muted)
                            }
                        }
                        .padding(8)
                        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct InvestmentPlanCard: View {
    let plan: PersonalInvestmentPlan

    private var accent: Color {
        if plan.isEndedPlan {
            return AppPalette.muted
        }
        if plan.isPausedPlan {
            return AppPalette.warning
        }
        return plan.isSmartPlan ? AppPalette.info : AppPalette.brand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.planTypeLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                        Text(plan.fundName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(2)
                        if plan.isDrawdownMode {
                            ToolbarBadge(title: "涨跌幅模式", tint: AppPalette.info)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(plan.scheduleText)
                        if let fundCode = plan.fundCode, !fundCode.isEmpty {
                            Text(fundCode)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(plan.amountRangeText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(plan.normalizedStatus)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 10) {
                LabeledValue(title: "累计期数", value: plan.investedPeriods.map(String.init) ?? "—")
                LabeledValue(title: "累计投入", value: plan.cumulativeInvestedAmount.map(currencyText) ?? "—")
                LabeledValue(title: "支付方式", value: plan.paymentMethod ?? "—")
                LabeledValue(title: "下次执行", value: plan.nextExecutionDate.isEmpty ? "—" : plan.nextExecutionDate)
            }

            if let note = plan.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(5)
            }
        }
        .padding(12)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PendingTradeCard: View {
    let trade: PersonalPendingTrade

    private var accent: Color {
        switch trade.actionLabel {
        case "买入", "定投":
            return AppPalette.danger
        case "转换":
            return AppPalette.info
        default:
            return AppPalette.brand
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(trade.actionLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                        Text(trade.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(2)
                    }

                    if let codeText = trade.displayCodeText, !codeText.isEmpty {
                        Text(codeText)
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(trade.amountText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(trade.status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.brand)
                }
            }

            HStack {
                Text(trade.occurredAt)
                Spacer()
                if let note = trade.note, !note.isEmpty {
                    Text(note)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
        }
        .padding(12)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
