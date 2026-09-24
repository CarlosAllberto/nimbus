import SwiftUI

struct FormFieldsSliceA: View {
    let kind: FormToolKind
    @Binding var canSubmit: Bool
    @Binding var fields: [String: String]
    @Binding var files: [String: URL]
    /// Which step to render, for the tools `FormToolKind.steps` splits up.
    /// Always 0 for the single-page forms, which ignore it entirely.
    var step: Int = 0
    /// One flag per step, so the shell knows whether "Next" can be enabled.
    /// Written by the same `update…State()` that already computes
    /// `canSubmit`, since it reads every field regardless of which step is
    /// on screen — a step the user hasn't reached yet is simply not valid
    /// yet, which is exactly the answer wanted.
    @Binding var stepValidity: [Bool]

    // WHOIS Scan
    @State private var domain = ""

    // DNS Check
    @State private var dnsHost = ""
    @State private var dnsRecordType = "A"

    // Site Speed
    @State private var siteSpeedURL = ""
    @State private var siteSpeedStrategy = "mobile"

    // WordPress Inspector
    @State private var wordpressURL = ""

    // Policy Generator
    @State private var policyCompanyName = ""
    @State private var policyCompanyURL = ""

    // QR Code
    @State private var qrContent = ""
    @State private var qrIconURL: URL?

    // Contract PDF
    @State private var clientName = ""
    @State private var clientCPF = ""
    @State private var clientEmail = ""
    @State private var clientPhone = ""
    @State private var clientAddress = ""
    @State private var contractorCompanyName = ""
    @State private var contractorCNPJ = ""
    @State private var contractorAddress = ""
    @State private var venueCity = ""
    @State private var venueState = ""
    @State private var serviceDescription = ""
    @State private var serviceTermWeeks = 0
    @State private var serviceValue = 0.0
    @State private var signaturePlaceDate = ""
    @State private var signatory1 = ""
    @State private var signatory2 = ""

    private static let dnsRecordTypes = ["A", "AAAA", "CNAME", "MX", "TXT", "NS", "SOA", "CAA"]

    private static let brlCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    private struct ContractPDFFields: Encodable {
        let nome, cpf, email, telefone, endereco: String
        let tipoServico, prazo, valor, localData: String
        let razaoSocialContratada, cnpjContratada, enderecoContratada: String
        let cidadeForo, ufForo: String
    }

    var body: some View {
        switch kind {
        case .whoisScan: whoisScanFields
        case .dnsCheck: dnsCheckFields
        case .siteSpeed: siteSpeedFields
        case .wordpressInspector: wordpressInspectorFields
        case .policyGenerator: policyGeneratorFields
        case .contractPDF: contractPDFFields
        case .qrCode: qrCodeFields
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var whoisScanFields: some View {
        FormRow(label: "Domain") {
            TextField("example.com", text: $domain)
                .formFieldChrome()
                .accessibilityLabel("Domain")
        }
        .onChange(of: domain) { updateWhoisScanState() }
        .task { updateWhoisScanState() }
    }

    private func updateWhoisScanState() {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmed.isEmpty
        fields["domain"] = trimmed
    }

    @ViewBuilder
    private var dnsCheckFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Host/Domain") {
                TextField("example.com", text: $dnsHost)
                    .formFieldChrome()
                    .accessibilityLabel("Host or Domain")
            }
            FormRow(label: "Record Type") {
                menuPicker("Record Type", selection: $dnsRecordType, options: Self.dnsRecordTypes.map { ($0, $0) }, width: 100)
            }
        }
        .onChange(of: dnsHost) { updateDNSCheckState() }
        .onChange(of: dnsRecordType) { updateDNSCheckState() }
        .task { updateDNSCheckState() }
    }

    private func updateDNSCheckState() {
        let trimmed = dnsHost.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmed.isEmpty
        fields["domain"] = trimmed
        fields["type"] = dnsRecordType
    }

    @ViewBuilder
    private var siteSpeedFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "URL") {
                TextField("https://example.com", text: $siteSpeedURL)
                    .formFieldChrome()
                    .accessibilityLabel("URL")
            }
            FormRow(label: "Strategy") {
                Picker("Strategy", selection: $siteSpeedStrategy) {
                    Text("Mobile").tag("mobile")
                    Text("Desktop").tag("desktop")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200, alignment: .leading)
                .accessibilityLabel("Strategy")
            }
        }
        .onChange(of: siteSpeedURL) { updateSiteSpeedState() }
        .onChange(of: siteSpeedStrategy) { updateSiteSpeedState() }
        .task { updateSiteSpeedState() }
    }

    private func updateSiteSpeedState() {
        let trimmed = siteSpeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmed.isEmpty
        fields["url"] = trimmed
        fields["strategy"] = siteSpeedStrategy
    }

    @ViewBuilder
    private var wordpressInspectorFields: some View {
        FormRow(label: "URL") {
            TextField("https://example.com", text: $wordpressURL)
                .formFieldChrome()
                .accessibilityLabel("URL")
        }
        .onChange(of: wordpressURL) { updateWordPressInspectorState() }
        .task { updateWordPressInspectorState() }
    }

    private func updateWordPressInspectorState() {
        let trimmed = wordpressURL.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmed.isEmpty
        fields["url"] = trimmed
    }

    @ViewBuilder
    private var policyGeneratorFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Company Name") {
                TextField("Acme Inc.", text: $policyCompanyName)
                    .formFieldChrome()
                    .accessibilityLabel("Company Name")
            }
            FormRow(label: "Company URL") {
                TextField("https://example.com", text: $policyCompanyURL)
                    .formFieldChrome()
                    .accessibilityLabel("Company URL")
            }
        }
        .onChange(of: policyCompanyName) { updatePolicyGeneratorState() }
        .onChange(of: policyCompanyURL) { updatePolicyGeneratorState() }
        .task { updatePolicyGeneratorState() }
    }

    private func updatePolicyGeneratorState() {
        let trimmedName = policyCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = policyCompanyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmedName.isEmpty && !trimmedURL.isEmpty
        fields["companyName"] = trimmedName
        fields["companyUrl"] = trimmedURL
    }

    @ViewBuilder
    private var qrCodeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(label: "Content") {
                FormTextEditor(
                    text: $qrContent,
                    label: "Content",
                    placeholder: "A URL, some text, contact details…",
                    minHeight: 120,
                    fillsHeight: true
                )
            }
            FormRow(label: "Center Icon", isOptional: true) {
                CompactFileField(label: "Center Icon", acceptance: .image, url: $qrIconURL)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: qrContent) { updateQRCodeState() }
        .onChange(of: qrIconURL) { updateQRCodeState() }
        .task { updateQRCodeState() }
    }

    private func updateQRCodeState() {
        let trimmed = qrContent.trimmingCharacters(in: .whitespacesAndNewlines)
        canSubmit = !trimmed.isEmpty
        fields["data"] = trimmed
        fields["format"] = "svg"
        files["icon"] = qrIconURL
    }

    @ViewBuilder
    private var contractPDFFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case 0: contractPDFClientSection
            case 1: contractPDFContractorSection
            case 2: contractPDFVenueSection
            case 3: contractPDFServiceSection
            default: contractPDFSignatureSection
            }
        }
        .task { updateContractPDFState() }
    }


    private var contractPDFClientSection: some View {
        Group {
            FormSectionHeader(title: "Client")
            FormRow(label: "Name") {
                TextField("Full name", text: $clientName)
                    .formFieldChrome()
                    .accessibilityLabel("Client Name")
            }
            FormRow(label: "CPF") {
                TextField("000.000.000-00", text: $clientCPF)
                    .formFieldChrome()
                    .accessibilityLabel("Client CPF")
            }
            FormRow(label: "Email") {
                TextField("name@example.com", text: $clientEmail)
                    .formFieldChrome()
                    .accessibilityLabel("Client Email")
            }
            FormRow(label: "Phone") {
                TextField("+55 11 90000-0000", text: $clientPhone)
                    .formFieldChrome()
                    .accessibilityLabel("Client Phone")
            }
            FormRow(label: "Address") {
                TextField("Street, number, city", text: $clientAddress)
                    .formFieldChrome()
                    .accessibilityLabel("Client Address")
            }
        }
        .onChange(of: clientName) { updateContractPDFState() }
        .onChange(of: clientCPF) { updateContractPDFState() }
        .onChange(of: clientEmail) { updateContractPDFState() }
        .onChange(of: clientPhone) { updateContractPDFState() }
        .onChange(of: clientAddress) { updateContractPDFState() }
    }

    private var contractPDFContractorSection: some View {
        Group {
            FormSectionHeader(title: "Contractor")
            FormRow(label: "Company Name") {
                TextField("Legal company name", text: $contractorCompanyName)
                    .formFieldChrome()
                    .accessibilityLabel("Contractor Company Name")
            }
            FormRow(label: "CNPJ") {
                TextField("00.000.000/0000-00", text: $contractorCNPJ)
                    .formFieldChrome()
                    .accessibilityLabel("Contractor CNPJ")
            }
            FormRow(label: "Address") {
                TextField("Street, number, city", text: $contractorAddress)
                    .formFieldChrome()
                    .accessibilityLabel("Contractor Address")
            }
        }
        .onChange(of: contractorCompanyName) { updateContractPDFState() }
        .onChange(of: contractorCNPJ) { updateContractPDFState() }
        .onChange(of: contractorAddress) { updateContractPDFState() }
    }

    private var contractPDFVenueSection: some View {
        Group {
            FormSectionHeader(title: "Venue")
            FormRow(label: "City") {
                TextField("City where disputes are settled", text: $venueCity)
                    .formFieldChrome()
                    .accessibilityLabel("Venue City")
            }
            FormRow(label: "State/UF") {
                TextField("SP", text: $venueState)
                    .formFieldChrome()
                    .accessibilityLabel("Venue State or UF")
            }
        }
        .onChange(of: venueCity) { updateContractPDFState() }
        .onChange(of: venueState) { updateContractPDFState() }
    }

    private var contractPDFServiceSection: some View {
        Group {
            FormSectionHeader(title: "Service")
            FormRow(label: "Description") {
                TextField("e.g. Website design and development", text: $serviceDescription)
                    .formFieldChrome()
                    .accessibilityLabel("Service Description")
            }
            FormRow(label: "Term in Weeks") {
                TextField("Weeks", value: $serviceTermWeeks, format: .number)
                    .frame(width: 80)
                    .formFieldChrome()
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Term in Weeks")
            }
            FormRow(label: "Value") {
                TextField("Value", value: $serviceValue, format: .number)
                    .frame(width: 120)
                    .formFieldChrome()
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Value")
            }
        }
        .onChange(of: serviceDescription) { updateContractPDFState() }
        .onChange(of: serviceTermWeeks) { updateContractPDFState() }
        .onChange(of: serviceValue) { updateContractPDFState() }
    }

    private var contractPDFSignatureSection: some View {
        Group {
            FormSectionHeader(title: "Signature")
            FormRow(label: "Place/Date") {
                TextField("City, date", text: $signaturePlaceDate)
                    .formFieldChrome()
                    .accessibilityLabel("Signature Place and Date")
            }
            FormRow(label: "Signatory 1") {
                TextField("Name of the first signer", text: $signatory1)
                    .formFieldChrome()
                    .accessibilityLabel("Signatory 1")
            }
            FormRow(label: "Signatory 2") {
                TextField("Name of the second signer", text: $signatory2)
                    .formFieldChrome()
                    .accessibilityLabel("Signatory 2")
            }
        }
        .onChange(of: signaturePlaceDate) { updateContractPDFState() }
        .onChange(of: signatory1) { updateContractPDFState() }
        .onChange(of: signatory2) { updateContractPDFState() }
    }

    private func updateContractPDFState() {
        let textFields = [
            clientName, clientCPF, clientEmail, clientPhone, clientAddress,
            contractorCompanyName, contractorCNPJ, contractorAddress,
            venueCity, venueState, serviceDescription,
            signaturePlaceDate, signatory1, signatory2
        ]
        let allTextFilled = textFields.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        canSubmit = allTextFilled && serviceTermWeeks > 0 && serviceValue > 0

        func filled(_ values: String...) -> Bool {
            values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        // Same order as `FormToolKind.steps`.
        stepValidity = [
            filled(clientName, clientCPF, clientEmail, clientPhone, clientAddress),
            filled(contractorCompanyName, contractorCNPJ, contractorAddress),
            filled(venueCity, venueState),
            filled(serviceDescription) && serviceTermWeeks > 0 && serviceValue > 0,
            filled(signaturePlaceDate, signatory1, signatory2)
        ]

        let contractFields = ContractPDFFields(
            nome: clientName, cpf: clientCPF, email: clientEmail, telefone: clientPhone, endereco: clientAddress,
            tipoServico: serviceDescription,
            prazo: "\(serviceTermWeeks) semanas",
            valor: Self.brlCurrencyFormatter.string(from: NSNumber(value: serviceValue)) ?? String(serviceValue),
            localData: signaturePlaceDate,
            razaoSocialContratada: contractorCompanyName, cnpjContratada: contractorCNPJ, enderecoContratada: contractorAddress,
            cidadeForo: venueCity, ufForo: venueState
        )
        if let data = try? JSONEncoder().encode(contractFields), let json = String(data: data, encoding: .utf8) {
            fields["contractFields"] = json
        }
        fields["signer1Label"] = signatory1
        fields["signer2Label"] = signatory2
    }

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
}
