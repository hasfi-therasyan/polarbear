
import Foundation
import CoreBluetooth
import RxSwift

public class BleHrClient: BleGattClientBase {
    public static let HR_SERVICE     = CBUUID(string: "180D")
    let BODY_SENSOR_LOCATION         = CBUUID(string: "2a38")
    public static let HR_MEASUREMENT = CBUUID(string: "2a37")
    public typealias BleHrNotification = (hr: Int, sensorContact: Bool, sensorContactSupported: Bool, energy: Int, rrs: [Int])
    
    private(set) var observers = AtomicList<RxObserver<BleHrNotification>>()
    private let disposeBag = DisposeBag()
    
    public init(gattServiceTransmitter: BleAttributeTransportProtocol){
        super.init(serviceUuid: BleHrClient.HR_SERVICE, gattServiceTransmitter: gattServiceTransmitter)
        addCharacteristicRead(BODY_SENSOR_LOCATION)
    }
    
    // from base
    override public func disconnected() {
        super.disconnected()
        RxUtils.postErrorAndClearList(observers, error: BleGattException.gattDisconnected)
    }
    
    // from base
    override public func processServiceData(_ chr: CBUUID , data: Data , err: Int ){
        if( chr.isEqual(BleHrClient.HR_MEASUREMENT) && err == 0 ){
            var offset=0
            let hrFormat = data[0] & 0x01
            let sensorContact = ((data[0] & 0x06) >> 1) == 0x03
            let contactSupported = (data[0] & 0x04) != 0           
            let energyExpended = (data[0] & 0x08) >> 3
            let rrPresent = (data[0] & 0x10) >> 4
            
            let hrValue = hrFormat == 1 ? (Int(data[1]) + (Int(data[2]) << 8)) : Int(data[1])
            offset = Int(hrFormat) + 2
            var energy = 0
            if (energyExpended == 1) {
                energy = Int(data[offset]) + (Int(data[offset + 1]) << 8)
                offset += 2
            }
            var rrs = [Int]()
            if( rrPresent == 1 ){
                let len = data.count
                while (offset < len) {
                    let rrValueRaw = Int(data[offset]) | (Int(data[offset + 1]) << 8)
                    offset += 2
                    rrs.append(rrValueRaw)
                }
            }
            RxUtils.emitNext(observers) { (observer) in
                observer.obs.onNext((hr: hrValue, sensorContact: sensorContact, sensorContactSupported: contactSupported,energy: energy,rrs: rrs))
            }
         }
    }
    
    /// Observable for observing heart rate data from BLE HR Service
    ///
    /// - Parameter checkConnection: if connection is checked on start of observation
    /// - Returns: observable stream of heart rate  data
    public func observeHrNotifications(_ checkConnection: Bool) -> Observable<BleHrNotification> {
        return enableNotifications()
            .andThen(RxUtils.monitor(observers, transport: gattServiceTransmitter, checkConnection: checkConnection)
                        .do( onDispose: {
                            [weak self] in
                            guard let self = self else {
                                return
                            }
                            self.disableNotifications()
                                .subscribe()
                                .disposed(by: self.disposeBag)
                        })
            )
            .share(replay: 0)
    }
    
    private func enableNotifications() -> Completable {
        BleLogger.trace("Enable HR notifications")
        return enableCharacteristicNotification(serviceUUID: BleHrClient.HR_SERVICE, chr: BleHrClient.HR_MEASUREMENT)
    }
    
    private func disableNotifications() -> Completable {
        BleLogger.trace("Disable HR notifications. Is disable sent: \(observers.items.isEmpty)")
        if(observers.items.isEmpty) {
            return disableCharacteristicNotification(serviceUUID: BleHrClient.HR_SERVICE, chr: BleHrClient.HR_MEASUREMENT)
        } else {
            return Completable.empty()
        }
    }
}
