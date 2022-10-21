//
//  SourcepointClientCoordinator.swift
//  Pods
//
//  Created by Andre Herculano on 14.09.22.
//
// swiftlint:disable type_body_length file_length

import Foundation

typealias LoadMessagesReturnType = ([MessageToDisplay], SPUserData)
typealias MessagesAndConsentsHandler = (Result<LoadMessagesReturnType, SPError>) -> Void
struct MessageToDisplay {
    let message: Message
    let metadata: MessageMetaData
    let url: URL
    let type: SPCampaignType
    let childPmId: String?
}
extension MessageToDisplay {
    init?(_ campaign: Campaign) {
        guard let message = campaign.message,
                let metadata = campaign.messageMetaData,
                let url = campaign.url
        else {
            return nil
        }

        self.message = message
        self.metadata = metadata
        self.url = url
        self.type = campaign.type
        switch campaign.userConsent {
            case .ccpa(let consents): childPmId = consents.childPmId
            case .gdpr(let consents): childPmId = consents.childPmId
            default: childPmId = nil
        }
    }
}

protocol SPClientCoordinator {
    var authId: String? { get set }

    func loadMessages(_ handler: @escaping MessagesAndConsentsHandler)
    func reportAction(_ action: SPAction, handler: @escaping (Result<SPUserData, SPError>) -> Void)
}

class SourcepointClientCoordinator: SPClientCoordinator {
    static let sampleRate = 1

    struct State: Codable {
        struct GDPRMetaData: Codable {
            var additionsChangeDate, legalBasisChangeDate: SPDateCreated
        }

        var gdpr: SPGDPRConsent?
        var ccpa: SPCCPAConsent?
        var gdprMetadata: GDPRMetaData?
        var wasSampled: Bool?
        var localState: SPJson?
        var nonKeyedLocalState: SPJson?

        mutating func udpateGDPRStatus() {
            guard let gdpr = gdpr, let gdprMetadata = gdprMetadata else { return }
            var shouldUpdateConsentedAll = false
            if gdpr.dateCreated.date < gdprMetadata.additionsChangeDate.date {
                self.gdpr?.consentStatus.vendorListAdditions = true
                shouldUpdateConsentedAll = true
            }
            if gdpr.dateCreated.date < gdprMetadata.legalBasisChangeDate.date {
                self.gdpr?.consentStatus.legalBasisChanges = true
                shouldUpdateConsentedAll = true
            }
            if self.gdpr?.consentStatus.consentedAll == true, shouldUpdateConsentedAll {
                self.gdpr?.consentStatus.granularStatus?.previousOptInAll = true
                self.gdpr?.consentStatus.consentedAll = false
            }
        }
    }

    let accountId, propertyId: Int
    let propertyName: SPPropertyName
    var authId: String?
    let language: SPMessageLanguage
    let idfaStatus: SPIDFAStatus
    let campaigns: SPCampaigns
    var pubData: SPPublisherData

    let spClient: SourcePointProtocol
    var storage: SPLocalStorage

    var state: State

    /// Checks if this user has data from the previous version of the SDK (v6).
    /// This check should only done once so we remove the data stored by the older SDK and return false after that.
    var migratingUser: Bool {
        if storage.localState != nil {
            storage.localState = nil
            return true
        }
        return false
    }

    var shouldCallConsentStatus: Bool {
        authId != nil || migratingUser
    }

    var shouldCallMessages: Bool {
        (state.gdpr?.applies == true && state.gdpr?.consentStatus.consentedAll != true) ||
        state.ccpa?.applies == true ||
        campaigns.ios14 != nil
    }

    var metaDataParamsFromState: MetaDataBodyRequest {
        .init(
            gdpr: .init(
                hasLocalData: state.gdpr?.uuid != nil,
                dateCreated: state.gdpr?.dateCreated,
                uuid: state.gdpr?.uuid
            ),
            ccpa: .init(
                hasLocalData: state.ccpa?.uuid != nil,
                dateCreated: state.ccpa?.dateCreated,
                uuid: state.ccpa?.uuid
            )
        )
    }

    var pvDataBodyFromState: PvDataRequestBody {
        var gdpr: PvDataRequestBody.GDPR?
        var ccpa: PvDataRequestBody.CCPA?
        if let stateGDPR = state.gdpr {
            gdpr = PvDataRequestBody.GDPR(
                applies: stateGDPR.applies,
                uuid: stateGDPR.uuid,
                accountId: accountId,
                siteId: propertyId,
                consentStatus: stateGDPR.consentStatus,
                pubData: pubData,
                sampleRate: SourcepointClientCoordinator.sampleRate,
                euconsent: stateGDPR.euconsent,
                msgId: stateGDPR.lastMessage?.id,
                categoryId: stateGDPR.lastMessage?.categoryId,
                subCategoryId: stateGDPR.lastMessage?.subCategoryId,
                prtnUUID: stateGDPR.lastMessage?.partitionUUID
            )
        }
        if let stateCCPA = state.ccpa {
            ccpa = .init(
                applies: stateCCPA.applies,
                uuid: stateCCPA.uuid,
                accountId: accountId,
                siteId: propertyId,
                consentStatus: stateCCPA.consentStatus,
                pubData: pubData,
                messageId: stateCCPA.lastMessage?.id,
                sampleRate: SourcepointClientCoordinator.sampleRate
            )
        }
        return .init(gdpr: gdpr, ccpa: ccpa)
    }

    var messagesParamsFromState: MessagesRequest {
        .init(
            body: .init(
                propertyHref: propertyName,
                accountId: accountId,
                campaigns: .init(
                    ccpa: .init(
                        targetingParams: campaigns.gdpr?.targetingParams,
                        hasLocalData: state.ccpa?.uuid != nil,
                        status: state.ccpa?.status
                    ),
                    gdpr: .init(
                        targetingParams: campaigns.gdpr?.targetingParams,
                        hasLocalData: state.gdpr?.uuid != nil,
                        consentStatus: state.gdpr?.consentStatus
                    ),
                    ios14: .init(
                        targetingParams: campaigns.ios14?.targetingParams,
                        idfaSstatus: idfaStatus
                    )
                ),
                localState: state.localState,
                consentLanguage: language,
                campaignEnv: campaigns.environment,
                idfaStatus: idfaStatus
            ),
            metadata: .init(
                ccpa: .init(applies: state.ccpa?.applies),
                gdpr: .init(applies: state.gdpr?.applies)
            ),
            nonKeyedLocalState: state.nonKeyedLocalState
        )
    }

    var userData: SPUserData {
        SPUserData(
            gdpr: campaigns.gdpr != nil ?
                .init(consents: state.gdpr, applies: state.gdpr?.applies ?? false) :
                nil,
            ccpa: campaigns.ccpa != nil ?
                .init(consents: state.ccpa, applies: state.ccpa?.applies ?? false) :
                nil
        )
    }

    init(
        accountId: Int,
        propertyName: SPPropertyName,
        propertyId: Int,
        authId: String? = nil,
        language: SPMessageLanguage = .BrowserDefault,
        campaigns: SPCampaigns,
        idfaStatus: SPIDFAStatus = .unknown,
        pubData: SPPublisherData = SPPublisherData(),
        storage: SPLocalStorage = SPUserDefaults(),
        spClient: SourcePointProtocol? = nil
    ) {
        self.accountId = accountId
        self.propertyId = propertyId
        self.propertyName = propertyName
        self.authId = authId
        self.language = language
        self.campaigns = campaigns
        self.idfaStatus = idfaStatus
        self.pubData = pubData
        self.storage = storage

        self.state = State(
            gdpr: campaigns.gdpr != nil ? .empty() : nil,
            ccpa: campaigns.ccpa != nil ? .empty() : nil
        )

        guard let spClient = spClient else {
            self.spClient = SourcePointClient(
                accountId: accountId,
                propertyName: propertyName,
                campaignEnv: campaigns.environment,
                timeout: SPConsentManager.DefaultTimeout
            )
            return
        }
        self.spClient = spClient
    }

    func loadMessages(_ handler: @escaping MessagesAndConsentsHandler) {
        metaData {
            self.consentStatus {
                self.state.udpateGDPRStatus()
                self.messages(handler)
            }
        }
        pvData()
    }

    func handleMetaDataResponse(_ response: MetaDataResponse) {
        if let gdprMetaData = response.gdpr {
            state.gdpr?.applies = gdprMetaData.applies
            state.gdprMetadata = .init(
                additionsChangeDate: gdprMetaData.additionsChangeDate,
                legalBasisChangeDate: gdprMetaData.legalBasisChangeDate
            )
        }
        if let ccpaMetaData = response.ccpa {
            state.ccpa?.applies = ccpaMetaData.applies
        }
    }

    func metaData(next: @escaping () -> Void) {
        spClient.metaData(
            accountId: accountId,
            propertyId: propertyId,
            metadata: metaDataParamsFromState
        ) { result in
            switch result {
                case .success(let response):
                    self.handleMetaDataResponse(response)
                case .failure(let error):
                    print(error)
            }
            next()
        }
    }

    func consentStatusMetadataFromState(_ campaign: CampaignConsent?) -> ConsentStatusMetaData.Campaign? {
        guard let campaign = campaign else { return nil }
        return ConsentStatusMetaData.Campaign(
            hasLocalData: true,
            applies: campaign.applies,
            dateCreated: campaign.dateCreated,
            uuid: campaign.uuid
        )
    }

    func handleConsentStatusResponse(_ response: ConsentStatusResponse) {
        state.localState = response.localState
        state.gdpr = SPGDPRConsent(from: response.consentStatusData.gdpr)
        state.ccpa = SPCCPAConsent(from: response.consentStatusData.ccpa)
    }

    func consentStatus(next: @escaping () -> Void) {
        if shouldCallConsentStatus {
            spClient.consentStatus(
                propertyId: propertyId,
                metadata: .init(
                    gdpr: consentStatusMetadataFromState(state.gdpr),
                    ccpa: consentStatusMetadataFromState(state.ccpa)
                ),
                authId: authId
            ) { result in
                switch result {
                    case .success(let response):
                        self.handleConsentStatusResponse(response)
                    case .failure(let error):
                        print(error)
                }
                next()
            }
        } else {
            next()
        }
    }

    func handleMessagesResponse(_ response: MessagesResponse) -> LoadMessagesReturnType {
        state.localState = response.localState
        state.nonKeyedLocalState = response.nonKeyedLocalState
        let messages = response.campaigns.compactMap { MessageToDisplay($0) }
        messages.forEach {
            if $0.type == .gdpr {
                state.gdpr?.lastMessage = LastMessageData(from: $0.metadata)
            } else if $0.type == .ccpa {
                state.ccpa?.lastMessage = LastMessageData(from: $0.metadata)
            }
        }
        return (messages, userData)
    }

    func messages(_ handler: @escaping MessagesAndConsentsHandler) {
        if shouldCallMessages {
            spClient.getMessages(messagesParamsFromState) { result in
                switch result {
                    case .success(let response):
                        handler(Result.success(self.handleMessagesResponse(response)))
                    case .failure(let error):
                        handler(Result.failure(error))
                }
            }
        } else {
            handler(Result.success(([], userData)))
        }
    }

    func sample(_ lambda: (Bool) -> Void, at percentage: Int = sampleRate) {
        let hit = 1...percentage ~= Int.random(in: 1...100)
        lambda(hit)
    }

    func pvData() {
        guard let wasSampled = state.wasSampled else {
            sample { hit in
                if hit {
                    spClient.pvData(pvDataBodyFromState)
                }
                state.wasSampled = hit
            }
            return
        }

        if wasSampled {
            spClient.pvData(pvDataBodyFromState)
        }
    }

    func getChoiceAll(_ action: SPAction, handler: @escaping (Result<ChoiceAllResponse?, SPError>) -> Void) {
        if action.type == .AcceptAll || action.type == .RejectAll {
            spClient.choiceAll(
                actionType: action.type,
                accountId: accountId,
                propertyId: propertyId,
                metadata: .init(
                    gdpr: campaigns.gdpr != nil ? .init(applies: state.gdpr?.applies ?? false) : nil,
                    ccpa: campaigns.ccpa != nil ? .init(applies: state.ccpa?.applies ?? false) : nil
                )
            ) { result in handler(Result {
                    try? result.get()
                }.mapError { _ in
                    SPError()
                }) // TODO: map to correct error
            }
        } else {
            handler(Result {
                nil
            }.mapError { _ in
                SPError()
            }) // TODO: map to correct error
        }
    }

    func postChoice(_ action: SPAction, postPayloadFromGetCall: ChoiceAllResponse.GDPR.PostPayload?, handler: @escaping (Result<String, SPError>) -> Void) {
        if action.campaignType == .gdpr {
            spClient.postGDPRAction(
                actionType: action.type,
                body: GDPRChoiceBody(
                    authId: self.authId,
                    uuid: self.state.gdpr?.uuid,
                    propertyId: String(self.propertyId),
                    messageId: String(self.state.gdpr?.lastMessage?.id ?? 0),
                    consentAllRef: postPayloadFromGetCall?.consentAllRef,
                    vendorListId: postPayloadFromGetCall?.vendorListId,
                    pubData: action.publisherData,
                    pmSaveAndExitVariables: nil,  // TODO: convert pm payload from SPAction to this class
                    sampleRate: SourcepointClientCoordinator.sampleRate,
                    idfaStatus: self.idfaStatus,
                    granularStatus: postPayloadFromGetCall?.granularStatus
                )
            ) { result in
                print(result)
            }
        }
    }

    func reportAction(_ action: SPAction, handler: @escaping (Result<SPUserData, SPError>) -> Void) {
        getChoiceAll(action) { getResult in
            switch getResult {
                case .success(let getResponse):
                    self.postChoice(action, postPayloadFromGetCall: getResponse?.gdpr?.postPayload) { postResult in
                        switch postResult {
                            case .success(let response):
                                print(response)
                            case .failure(let error):
                                // flag to sync again later
                                print(error)
                        }
                    }
                case .failure(let error):
                    print(error)
            }
        }
    }
}
