import SwiftUI

private struct JSONPropertyItem: Identifiable, Equatable {
    let id = UUID()
    var key = ""
    var value = ""
    var type = "string"
}

private struct CopyPageItem: Identifiable, Equatable {
    let id = UUID()
    var title = ""
    var sections = ""
}

struct FormFieldsSliceB: View {
    let kind: FormToolKind
    @Binding var canSubmit: Bool
    @Binding var fields: [String: String]
    @Binding var files: [String: URL]

    // Password Generator
    @State private var passwordBase = ""
    @State private var passwordLength = 16
    @State private var convertLettersToNumbers = false
    @State private var includeUppercase = true

    // Color Convert
    @State private var colorValue = ""

    // Contrast Check
    @State private var foregroundColor = ""
    @State private var backgroundColor = ""

    // WhatsApp Link
    @State private var waPhone = ""
    @State private var waMessage = ""
    @State private var waDestination = "wa.me"

    // HTML Minify
    @State private var htmlCode = ""

    // JS Minify
    @State private var jsCode = ""

    // JSON Creator
    @State private var jsonStructure = "object"
    @State private var jsonProperties: [JSONPropertyItem] = []

    // Responsive Font Clamp
    @State private var minViewportWidth = 320
    @State private var maxViewportWidth = 1440
    @State private var desktopFontSizes = ""
    @State private var mobileFontAuto = false
    @State private var mobileFontSize = ""
    @State private var fontClampUnit = "px"

    // Copy Generator
    @State private var useBriefingFile = false
    @State private var briefingFileURL: URL?
    @State private var siteDescription = ""
    @State private var copyPages: [CopyPageItem] = []
    @State private var additionalNotes = ""

    var body: some View {
        switch kind {
        case .passwordGenerator: passwordGeneratorFields
        case .colorConvert: colorConvertFields
        case .contrastCheck: contrastCheckFields
        case .waLink: waLinkFields
        case .htmlMinify: htmlMinifyFields
        case .jsMinify: jsMinifyFields
        case .jsonCreator: jsonCreatorFields
        case .responsiveFontClamp: responsiveFontClampFields
        case .copyGenerator: copyGeneratorFields
        default: EmptyView()
        }
    }

    // MARK: - Password Generator

    private var passwordGeneratorFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Base / Prefix", isOptional: true) {
                TextField("Optional", text: $passwordBase)
                    .formFieldChrome()
                    .accessibilityLabel("Base or prefix")
            }
            FormRow(label: "Length") {
                Stepper(value: $passwordLength, in: 8...64) {
                    Text("\(passwordLength) characters")
                }
                .accessibilityLabel("Password length")
                .accessibilityValue("\(passwordLength) characters")
            }
            Toggle("Convert Letters to Numbers", isOn: $convertLettersToNumbers)
                .accessibilityLabel("Convert letters to numbers")
            Toggle("Include Uppercase", isOn: $includeUppercase)
                .accessibilityLabel("Include uppercase letters")
        }
        .task { updatePasswordGeneratorCanSubmit() }
        .onChange(of: passwordBase) { _, _ in updatePasswordGeneratorCanSubmit() }
        .onChange(of: passwordLength) { _, _ in updatePasswordGeneratorCanSubmit() }
        .onChange(of: convertLettersToNumbers) { _, _ in updatePasswordGeneratorCanSubmit() }
        .onChange(of: includeUppercase) { _, _ in updatePasswordGeneratorCanSubmit() }
    }

    private func updatePasswordGeneratorCanSubmit() {
        canSubmit = (8...64).contains(passwordLength)
        fields["input"] = passwordBase
        fields["letterToNumber"] = convertLettersToNumbers ? "true" : "false"
        fields["enableUpperCase"] = includeUppercase ? "true" : "false"
        fields["length"] = String(passwordLength)
    }

    // MARK: - Color Convert

    private var colorConvertFields: some View {
        FormRow(label: "Color") {
            TextField("Hex, RGB, HSL…", text: $colorValue)
                .formFieldChrome()
                .accessibilityLabel("Color value")
        }
        .task { updateColorConvertCanSubmit() }
        .onChange(of: colorValue) { _, _ in updateColorConvertCanSubmit() }
    }

    private func updateColorConvertCanSubmit() {
        let trimmed = colorValue.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmed.isEmpty
        fields["color"] = trimmed
    }

    // MARK: - Contrast Check

    private var contrastCheckFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Foreground Color") {
                TextField("Hex, RGB, HSL…", text: $foregroundColor)
                    .formFieldChrome()
                    .accessibilityLabel("Foreground color")
            }
            FormRow(label: "Background Color") {
                TextField("Hex, RGB, HSL…", text: $backgroundColor)
                    .formFieldChrome()
                    .accessibilityLabel("Background color")
            }
        }
        .task { updateContrastCheckCanSubmit() }
        .onChange(of: foregroundColor) { _, _ in updateContrastCheckCanSubmit() }
        .onChange(of: backgroundColor) { _, _ in updateContrastCheckCanSubmit() }
    }

    private func updateContrastCheckCanSubmit() {
        let trimmedForeground = foregroundColor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBackground = backgroundColor.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmedForeground.isEmpty && !trimmedBackground.isEmpty
        fields["foreground"] = trimmedForeground
        fields["background"] = trimmedBackground
    }

    // MARK: - WhatsApp Link

    private var waLinkFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Phone") {
                TextField("e.g. +1 555 000 0000", text: $waPhone)
                    .formFieldChrome()
                    .accessibilityLabel("Phone number")
            }
            FormRow(label: "Message", isOptional: true) {
                proseEditor($waMessage, label: "Message", placeholder: "Hi! I saw your website and I'd like to know more about…", minHeight: 70)
            }
            FormRow(label: "Destination") {
                menuPicker("Destination", selection: $waDestination, options: [
                    ("wa.me", "wa.me"), ("api", "API"), ("web", "Web")
                ], width: 110)
            }
        }
        .task { updateWaLinkCanSubmit() }
        .onChange(of: waPhone) { _, _ in updateWaLinkCanSubmit() }
        .onChange(of: waMessage) { _, _ in updateWaLinkCanSubmit() }
        .onChange(of: waDestination) { _, _ in updateWaLinkCanSubmit() }
    }

    private func updateWaLinkCanSubmit() {
        let trimmedPhone = waPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmedPhone.isEmpty
        fields["phone"] = trimmedPhone
        fields["text"] = waMessage
        fields["type"] = waDestination
    }

    // MARK: - HTML Minify

    private var htmlMinifyFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Code") {
                // The minify/unminify picker for this tool lives beside the
                // action button in `FormToolView`, not here.
                codeEditor($htmlCode, label: "HTML code", placeholder: "Paste your HTML here")
            }
        }
        .frame(maxHeight: .infinity)
        .task { updateHtmlMinifyCanSubmit() }
        .onChange(of: htmlCode) { _, _ in updateHtmlMinifyCanSubmit() }
    }

    private func updateHtmlMinifyCanSubmit() {
        canSubmit = !htmlCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        fields["html"] = htmlCode
    }

    // MARK: - JS Minify

    private var jsMinifyFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Code") {
                // The minify/unminify picker for this tool lives beside the
                // action button in `FormToolView`, not here.
                codeEditor($jsCode, label: "JavaScript code", placeholder: "Paste your JavaScript here")
            }
        }
        .frame(maxHeight: .infinity)
        .task { updateJsMinifyCanSubmit() }
        .onChange(of: jsCode) { _, _ in updateJsMinifyCanSubmit() }
    }

    private func updateJsMinifyCanSubmit() {
        canSubmit = !jsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        fields["js"] = jsCode
    }

    // MARK: - JSON Creator

    private var jsonCreatorFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Structure") {
                menuPicker("Structure", selection: $jsonStructure, options: [
                    ("object", "Object"), ("array", "Array")
                ], width: 110)
            }
            FormRow(label: "Properties") {
                DynamicList(addLabel: "Add Property", items: $jsonProperties, newItem: { JSONPropertyItem() }) { $item, index in
                    HStack(spacing: 8) {
                        TextField("Key", text: $item.key)
                            .frame(width: 120)
                            .formFieldChrome()
                            .accessibilityLabel("Property \(index + 1) key")
                        TextField("Value", text: $item.value)
                            .frame(width: 140)
                            .formFieldChrome()
                            .accessibilityLabel("Property \(index + 1) value")
                        menuPicker("Type", selection: $item.type, options: [
                            ("string", "String"), ("number", "Number"), ("boolean", "Boolean"),
                            ("null", "Null"), ("object", "Object"), ("array", "Array")
                        ], width: 100)
                    }
                }
            }
        }
        .task { updateJsonCreatorCanSubmit() }
        .onChange(of: jsonStructure) { _, _ in updateJsonCreatorCanSubmit() }
        .onChange(of: jsonProperties) { _, _ in updateJsonCreatorCanSubmit() }
    }

    /// Bug fix (contract, Slice B item 3): array items have no key, so an
    /// array only needs at least one item; object still needs at least one
    /// non-empty key.
    private func updateJsonCreatorCanSubmit() {
        canSubmit = jsonStructure == "array"
            ? !jsonProperties.isEmpty
            : jsonProperties.contains { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        fields["structure"] = jsonStructure
        fields["properties"] = Self.encodeJSONProperties(jsonProperties)
    }

    private static func encodeJSONProperties(_ items: [JSONPropertyItem]) -> String {
        let payload = items.map { ["key": $0.key, "value": $0.value, "type": $0.type] }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    // MARK: - Responsive Font Clamp

    private var responsiveFontClampFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Min Viewport Width") {
                HStack(spacing: 6) {
                    TextField("Pixels", value: $minViewportWidth, format: .number)
                        .frame(width: 72)
                        .formFieldChrome()
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Minimum viewport width in pixels")
                    Text("px").foregroundStyle(.secondary)
                }
            }
            FormRow(label: "Max Viewport Width") {
                HStack(spacing: 6) {
                    TextField("Pixels", value: $maxViewportWidth, format: .number)
                        .frame(width: 72)
                        .formFieldChrome()
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Maximum viewport width in pixels")
                    Text("px").foregroundStyle(.secondary)
                }
            }
            FormRow(label: "Desktop Font Size(s)") {
                TextField("e.g. 16, 18, 24", text: $desktopFontSizes)
                    .formFieldChrome()
                    .accessibilityLabel("Desktop font sizes, comma separated")
            }
            Toggle("Auto Mobile Font Size", isOn: $mobileFontAuto.animation(.snappy))
                .accessibilityLabel("Automatic mobile font size")
            if !mobileFontAuto {
                FormRow(label: "Mobile Font Size") {
                    TextField("e.g. 14", text: $mobileFontSize)
                        .formFieldChrome()
                        .accessibilityLabel("Mobile font size")
                }
            }
            FormRow(label: "Unit") {
                menuPicker("Unit", selection: $fontClampUnit, options: [
                    ("px", "px"), ("rem", "rem")
                ], width: 90)
            }
        }
        .task { updateResponsiveFontClampCanSubmit() }
        .onChange(of: minViewportWidth) { _, _ in updateResponsiveFontClampCanSubmit() }
        .onChange(of: maxViewportWidth) { _, _ in updateResponsiveFontClampCanSubmit() }
        .onChange(of: desktopFontSizes) { _, _ in updateResponsiveFontClampCanSubmit() }
        .onChange(of: mobileFontAuto) { _, _ in updateResponsiveFontClampCanSubmit() }
        .onChange(of: mobileFontSize) { _, _ in updateResponsiveFontClampCanSubmit() }
        .onChange(of: fontClampUnit) { _, _ in updateResponsiveFontClampCanSubmit() }
    }

    private func updateResponsiveFontClampCanSubmit() {
        let desktopFilled = !desktopFontSizes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let mobileFilled = mobileFontAuto || !mobileFontSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        canSubmit = minViewportWidth < maxViewportWidth && desktopFilled && mobileFilled
        fields["desktopFont"] = desktopFontSizes
        fields["minViewport"] = String(minViewportWidth)
        fields["maxViewport"] = String(maxViewportWidth)
        fields["mobileFont"] = mobileFontAuto ? "" : mobileFontSize
        fields["unit"] = fontClampUnit
    }

    // MARK: - Copy Generator

    private var copyGeneratorFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Use Briefing File", isOn: $useBriefingFile.animation(.snappy))
                .accessibilityLabel("Use briefing file")
            // The briefing file and the written description are two ways of saying the
            // same thing, so exactly one of them is on screen at a time.
            if useBriefingFile {
                FormRow(label: "Briefing File") {
                    CompactFileField(label: "Briefing File", acceptance: .document, url: $briefingFileURL)
                }
            } else {
                FormRow(label: "Site Description") {
                    proseEditor($siteDescription, label: "Site description", placeholder: "What the site is about, who it is for, and the tone of voice it should use", minHeight: 100)
                }
            }
            FormRow(label: "Pages") {
                DynamicList(addLabel: "Add Page", items: $copyPages, newItem: { CopyPageItem() }) { $item, index in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Page Title", text: $item.title)
                            .formFieldChrome()
                            .accessibilityLabel("Page \(index + 1) title")
                        TextField("Hero, Pricing, FAQ", text: $item.sections)
                            .formFieldChrome()
                            .accessibilityLabel("Page \(index + 1) sections")
                    }
                }
            }
            FormRow(label: "Additional Notes", isOptional: true) {
                proseEditor($additionalNotes, label: "Additional notes", placeholder: "Anything else the copy should take into account", minHeight: 70)
            }
        }
        .task { updateCopyGeneratorCanSubmit() }
        .onChange(of: siteDescription) { _, _ in updateCopyGeneratorCanSubmit() }
        .onChange(of: copyPages) { _, _ in updateCopyGeneratorCanSubmit() }
        .onChange(of: useBriefingFile) { _, _ in updateCopyGeneratorCanSubmit() }
        .onChange(of: briefingFileURL) { _, _ in updateCopyGeneratorCanSubmit() }
        .onChange(of: additionalNotes) { _, _ in updateCopyGeneratorCanSubmit() }
    }

    private func updateCopyGeneratorCanSubmit() {
        let descriptionFilled = !siteDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasNamedPage = copyPages.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let briefingProvided = useBriefingFile ? briefingFileURL != nil : descriptionFilled
        canSubmit = briefingProvided && hasNamedPage

        files["file"] = useBriefingFile ? briefingFileURL : nil
        fields["siteDescription"] = siteDescription
        fields["copyObservations"] = additionalNotes
        fields["pagesConfig"] = Self.encodeCopyPages(copyPages)
    }

    private static func encodeCopyPages(_ items: [CopyPageItem]) -> String {
        let payload = items.map { ["title": $0.title, "sections": $0.sections] }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    // MARK: - Shared helpers

    private func menuPicker(
        _ label: String,
        selection: Binding<String>,
        options: [(String, String)],
        width: CGFloat
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width, alignment: .leading)
        .help(label)
    }

    private func codeEditor(_ text: Binding<String>, label: String, placeholder: String) -> some View {
        FormTextEditor(
            text: text,
            label: label,
            placeholder: placeholder,
            minHeight: 220,
            isMonospaced: true,
            fillsHeight: true
        )
    }

    private func proseEditor(
        _ text: Binding<String>,
        label: String,
        placeholder: String,
        minHeight: CGFloat
    ) -> some View {
        FormTextEditor(text: text, label: label, placeholder: placeholder, minHeight: minHeight)
    }
}
