import SwiftUI

struct PersonalInvestmentPlanAddSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var planTypeText = "定投"
    @State private var fundNameText = ""
    @State private var fundCodeText = ""
    @State private var scheduleText = ""
    @State private var amountText = ""
    @State private var investedPeriodsText = ""
    @State private var cumulativeAmountText = ""
    @State private var paymentMethodText = ""
    @State private var nextExecutionDateText = ""
    @State private var status: PersonalInvestmentPlanStatusOption = .active
    @State private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加计划档案")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("手动补录定投、智能定投或涨跌幅计划，保存后可继续修改状态。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                planField("计划类型", text: $planTypeText, placeholder: "定投 / 智能定投")
                planField("基金名称", text: $fundNameText, placeholder: "基金名称")
                planField("基金代码", text: $fundCodeText, placeholder: "例如 013308")
                planField("计划说明", text: $scheduleText, placeholder: "每周三定投 / 每周五定投-涨跌幅模式")
                planField("金额", text: $amountText, placeholder: "500.00元 / 250.00~1,000.00元")
                planField("已投期数", text: $investedPeriodsText, placeholder: "可留空")
                planField("累计投入", text: $cumulativeAmountText, placeholder: "可留空")
                planField("支付方式", text: $paymentMethodText, placeholder: "可留空")
                planField("下次执行", text: $nextExecutionDateText, placeholder: "进行中计划必填")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Picker("状态", selection: $status) {
                    ForEach(PersonalInvestmentPlanStatusOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
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

                Button("添加") {
                    if model.addInvestmentPlan(
                        planTypeLabel: planTypeText,
                        fundName: fundNameText,
                        fundCode: fundCodeText,
                        scheduleText: scheduleText,
                        amountText: amountText,
                        investedPeriodsText: investedPeriodsText,
                        cumulativeInvestedAmountText: cumulativeAmountText,
                        paymentMethod: paymentMethodText,
                        nextExecutionDate: nextExecutionDateText,
                        status: status.rawValue,
                        note: noteText
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.info)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func planField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
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

struct PersonalInvestmentPlanEditSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let plan: PersonalInvestmentPlan

    @State private var planTypeText: String
    @State private var fundNameText: String
    @State private var fundCodeText: String
    @State private var scheduleText: String
    @State private var amountText: String
    @State private var investedPeriodsText: String
    @State private var cumulativeAmountText: String
    @State private var paymentMethodText: String
    @State private var nextExecutionDateText: String
    @State private var status: PersonalInvestmentPlanStatusOption
    @State private var noteText: String

    init(plan: PersonalInvestmentPlan) {
        self.plan = plan
        _planTypeText = State(initialValue: plan.planTypeLabel)
        _fundNameText = State(initialValue: plan.fundName)
        _fundCodeText = State(initialValue: plan.fundCode ?? "")
        _scheduleText = State(initialValue: plan.scheduleText)
        _amountText = State(initialValue: plan.amountText)
        _investedPeriodsText = State(initialValue: plan.investedPeriods.map(String.init) ?? "")
        _cumulativeAmountText = State(initialValue: plan.cumulativeInvestedAmount.map { Self.amountFieldText($0) } ?? "")
        _paymentMethodText = State(initialValue: plan.paymentMethod ?? "")
        _nextExecutionDateText = State(initialValue: plan.nextExecutionDate)
        _status = State(initialValue: PersonalInvestmentPlanStatusOption(status: plan.normalizedStatus))
        _noteText = State(initialValue: plan.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("编辑定投计划")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(plan.fundCode.map { "\(plan.fundName)（\($0)）" } ?? plan.fundName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 10) {
                planField("计划类型", text: $planTypeText, placeholder: "定投 / 智能定投")
                planField("基金名称", text: $fundNameText, placeholder: "基金名称")
                planField("基金代码", text: $fundCodeText, placeholder: "例如 013308")
                planField("计划说明", text: $scheduleText, placeholder: "每周三定投 / 每周五定投-涨跌幅模式")
                planField("金额", text: $amountText, placeholder: "500.00元 / 250.00~1,000.00元")
                planField("已投期数", text: $investedPeriodsText, placeholder: "例如 12")
                planField("累计投入", text: $cumulativeAmountText, placeholder: "例如 6000.00")
                planField("支付方式", text: $paymentMethodText, placeholder: "余额宝")
                planField("下次执行", text: $nextExecutionDateText, placeholder: "2026-05-01(星期五)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                Picker("状态", selection: $status) {
                    ForEach(PersonalInvestmentPlanStatusOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
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

                Button("保存") {
                    if model.updateInvestmentPlan(
                        plan.id,
                        planTypeLabel: planTypeText,
                        fundName: fundNameText,
                        fundCode: fundCodeText,
                        scheduleText: scheduleText,
                        amountText: amountText,
                        investedPeriodsText: investedPeriodsText,
                        cumulativeInvestedAmountText: cumulativeAmountText,
                        paymentMethod: paymentMethodText,
                        nextExecutionDate: nextExecutionDateText,
                        status: status.rawValue,
                        note: noteText
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func planField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
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

    private static func amountFieldText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
