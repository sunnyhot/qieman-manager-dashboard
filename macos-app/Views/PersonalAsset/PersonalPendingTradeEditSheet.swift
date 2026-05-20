import SwiftUI

struct PersonalPendingTradeEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let trade: PersonalPendingTrade?

    @State private var occurredAtText: String
    @State private var actionText: String
    @State private var fundNameText: String
    @State private var fundCodeText: String
    @State private var targetFundNameText: String
    @State private var targetFundCodeText: String
    @State private var amountText: String
    @State private var statusText: String
    @State private var noteText: String

    init(trade: PersonalPendingTrade? = nil) {
        self.trade = trade
        _occurredAtText = State(initialValue: trade?.occurredAt ?? "")
        _actionText = State(initialValue: trade?.actionLabel ?? "买入")
        _fundNameText = State(initialValue: trade?.fundName ?? "")
        _fundCodeText = State(initialValue: trade?.fundCode ?? "")
        _targetFundNameText = State(initialValue: trade?.targetFundName ?? "")
        _targetFundCodeText = State(initialValue: trade?.targetFundCode ?? "")
        _amountText = State(initialValue: trade?.amountText ?? "")
        _statusText = State(initialValue: trade?.status ?? "交易进行中")
        _noteText = State(initialValue: trade?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trade == nil ? "添加买入中" : "修改买入中")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("记录待确认买入、定投或转换，后续可继续修改或删除。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                formField("发生时间", text: $occurredAtText, placeholder: "留空则使用当前时间")
                formField("动作", text: $actionText, placeholder: "买入 / 定投 / 转换")
                formField("基金名称", text: $fundNameText, placeholder: "可填名称或只填代码")
                formField("基金代码", text: $fundCodeText, placeholder: "例如 019524")
                formField("目标名称", text: $targetFundNameText, placeholder: "转换目标，可留空")
                formField("目标代码", text: $targetFundCodeText, placeholder: "转换目标代码，可留空")
                formField("金额/份额", text: $amountText, placeholder: "例如 10元 或 100份")
                formField("状态", text: $statusText, placeholder: "交易进行中")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                TextField("可留空", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                            .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(trade == nil ? "添加" : "保存") {
                    let didSave: Bool
                    if let trade {
                        didSave = model.updatePendingTrade(
                            trade.id,
                            occurredAt: occurredAtText,
                            actionLabel: actionText,
                            fundName: fundNameText,
                            fundCode: fundCodeText,
                            targetFundName: targetFundNameText,
                            targetFundCode: targetFundCodeText,
                            amountText: amountText,
                            status: statusText,
                            note: noteText
                        )
                    } else {
                        didSave = model.addPendingTrade(
                            occurredAt: occurredAtText,
                            actionLabel: actionText,
                            fundName: fundNameText,
                            fundCode: fundCodeText,
                            targetFundName: targetFundNameText,
                            targetFundCode: targetFundCodeText,
                            amountText: amountText,
                            status: statusText,
                            note: noteText
                        )
                    }
                    if didSave {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.warning)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.controlRadius)
                        .stroke(AppPalette.line.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

enum PersonalInvestmentPlanStatusOption: String, CaseIterable, Identifiable {
    case active = "进行中"
    case paused = "已暂停"
    case ended = "已终止"

    var id: String { rawValue }

    init(status: String) {
        if status.contains("终止") {
            self = .ended
        } else if status.contains("暂停") {
            self = .paused
        } else {
            self = .active
        }
    }

    var tint: Color {
        switch self {
        case .active:
            return AppPalette.positive
        case .paused:
            return AppPalette.warning
        case .ended:
            return AppPalette.muted
        }
    }
}
