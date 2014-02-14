# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class SmallParcel < Carrier
      self.retry_safe = true

      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"

      TEST_URL = "http://uat.wwex.com:8080/s3fWebService/services/SpeedShip2Service"
      LIVE_URL = "http://uat.wwex.com:8080/s3fWebService/services/SpeedShip2Service"

      #RESOURCES = {
      #    :rates => 'ups.app/xml/Rate',
      #    :track => 'ups.app/xml/Track'
      #}

      PICKUP_CODES = HashWithIndifferentAccess.new({
                                                       :daily_pickup => "01",
                                                       :customer_counter => "03",
                                                       :one_time_pickup => "06",
                                                       :on_call_air => "07",
                                                       :suggested_retail_rates => "11",
                                                       :letter_center => "19",
                                                       :air_service_center => "20"
                                                   })

      CUSTOMER_CLASSIFICATIONS = HashWithIndifferentAccess.new({
                                                                   :wholesale => "01",
                                                                   :occasional => "03",
                                                                   :retail => "04"
                                                               })

      # these are the defaults described in the UPS API docs,
      # but they don't seem to apply them under all circumstances,
      # so we need to take matters into our own hands
      DEFAULT_CUSTOMER_CLASSIFICATIONS = Hash.new do |hash, key|
        hash[key] = case key.to_sym
                      when :daily_pickup then
                        :wholesale
                      when :customer_counter then
                        :retail
                      else
                        :occasional
                    end
      end

      DEFAULT_SERVICES = {
          "01" => "UPS Next Day Air",
          "02" => "UPS Second Day Air",
          "03" => "UPS Ground",
          "07" => "UPS Worldwide Express",
          "08" => "UPS Worldwide Expedited",
          "11" => "UPS Standard",
          "12" => "UPS Three-Day Select",
          "13" => "UPS Next Day Air Saver",
          "14" => "UPS Next Day Air Early A.M.",
          "54" => "UPS Worldwide Express Plus",
          "59" => "UPS Second Day Air A.M.",
          "65" => "UPS Saver",
          "82" => "UPS Today Standard",
          "83" => "UPS Today Dedicated Courier",
          "84" => "UPS Today Intercity",
          "85" => "UPS Today Express",
          "86" => "UPS Today Express Saver"
      }


      TRACKING_STATUS_CODES = HashWithIndifferentAccess.new({
                                                                'I' => :in_transit,
                                                                'D' => :delivered,
                                                                'X' => :exception,
                                                                'P' => :pickup,
                                                                'M' => :manifest_pickup
                                                            })

      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]

      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]

      SHIPMENT_TYPE = {
          "For multi piece/package and single piece/package shipments" => "S",
          "For single piece/package return shipments" => "R"
      }

      DELIVERY_OPTION = {
          "Delivery Confirmation" => "1",
          "Signature Required" => "2",
          "Adult Signature Required" => "3"
      }

      PACKAGE_TYPE = {
          "Customer Packaging" => "00",
          "UPS Letter" => "01",
          "UPS Tube" => "03",
          "UPS PAK" => "04",
          "UPS Express Box - Small" => "S",
          "UPS Express Box - Medium" => "M",
          "UPS Express Box - Large" => "L"
      }

      def requirements
        [:loginId, :password, :licenseKey, :accountNumber]
      end

      def find_rates(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        main = create_xml(origin, destination, packages, options={})
        puts main
        response = commit(:rates, save_request(main.to_s), (options[:test] || false))
        parse_rate_response(origin, destination, packages, response, options)
      end

      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        #access_request = build_access_request()
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end

      def book_shipment(origin, destination, rates_response, options)
        main = create_xml(origin,destination,rates_response , options)


      end

      protected


      def create_xml(origin, destination, packages, options ={})
        header = XmlNode.new('soapenv:Header')
        body = XmlNode.new('soapenv:Body')
        main = XmlNode.new('soapenv:Envelope', {"xmlns:soapenv" => "http://schemas.xmlsoap.org/soap/envelope/",
                                                "xmlns:ser" => "http://service.v1.speedship2.s3f.soapservice.ws.wwex.com",
                                                "xmlns:xsd" => "http://common.v1.speedship2.s3f.soapservice.ws.wwex.com/xsd",
                                                "xmlns:xsd1" => "http://rateestimate.v1.speedship2.s3f.soapservice.ws.wwex.com/xsd"}) do |main_env|
          main_env << header
          main_env << body
        end
        build_access_request(header)
        build_rate_request(origin, destination, packages, body, options={})

        return main
      end


      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        else
          location
        end
      end

      def build_access_request(xml_request)
        xml_request << XmlNode.new('ser:authenticationDetail') do |authentication_detail|
          authentication_detail << XmlNode.new('ser:authenticationToken') do |access_request|
            access_request << XmlNode.new('xsd:loginId', @options[:loginId])
            access_request << XmlNode.new('xsd:password', @options[:password])
            access_request << XmlNode.new('xsd:licenseKey', @options[:licenseKey])
            access_request << XmlNode.new('xsd:accountNumber', @options[:accountNumber])
          end
        end
        xml_request.to_s
      end

      def build_rate_request(origin, destination, packages, xml_request, options={})
        imperial = ['US', 'LR', 'MM'].include?(origin.country)
        packages = Array(packages)

        xml_request << XmlNode.new('ser:getUPSServiceDetails') do |service_details|
          service_details << XmlNode.new('ser:upsServiceDetailRequest') do |detail_request|
            detail_request << XmlNode.new('xsd1:serviceOptions') do |service_options|
              build_service_options_node(service_options, options)
            end


            detail_request << XmlNode.new('xsd1:shipFrom') do |ship_from|
              build_location_node(origin, ship_from)
            end
            detail_request << XmlNode.new('xsd1:shipTo') do |ship_to|
              build_location_node(destination, ship_to)
            end


            detail_request << XmlNode.new('xsd1:shipmentPackages') do |shipments|
              build_shipment_packages(packages, imperial, shipments)
            end
          end
        end
        xml_request.to_s
      end

      def build_shipment_packages(packages, imperial, xml_request)
        packages.each do |package|
          xml_request << XmlNode.new('xsd:shipmentPackage') do |shipment_package|
            shipment_package << XmlNode.new('xsd:additonalHandling', package.options['additional_handling'])
            shipment_package << XmlNode.new('xsd:codPaymentForm', package.options['cod_payment_form'])
            shipment_package << XmlNode.new('xsd:codValue', package.options['value_cod'])
            shipment_package << XmlNode.new('xsd:confirmDeliveryOption', DELIVERY_OPTION[package.options['delivery_option']])
            shipment_package << XmlNode.new('xsd:handlingChargeAmount', package.options['handling_charge_amount'])
            shipment_package << XmlNode.new('xsd:handlingChargeUOM', package.options['UOM'])
            shipment_package << XmlNode.new('xsd:insuranceValue', package.options['insurance_value'])
            if imperial
              shipment_package << XmlNode.new('xsd:length', package.inches[0])
              shipment_package << XmlNode.new('xsd:width', package.inches[1])
              shipment_package << XmlNode.new('xsd:height', package.inches[2])
            else
              shipment_package << XmlNode.new('xsd:length', package.inches[0])
              shipment_package << XmlNode.new('xsd:width', package.inches[1])
              shipment_package << XmlNode.new('xsd:height', package.inches[2])

            end

            shipment_package << XmlNode.new('xsd:packageNumber', package.options['package_number'])
            if package.options['package_type'].present?
            shipment_package << XmlNode.new('xsd:packageType', PACKAGE_TYPE[package.options['package_type']])
            end
            shipment_package << XmlNode.new('xsd:largePackage', package.options['large_package'])
            shipment_package << XmlNode.new('xsd:weight', package.options['weight'])


          end

        end
      end


      def build_service_options_node(service_options, options= {})
        service_options << XmlNode.new('xsd1:additionalParameters') do |additional_parameter|
          if options[:additional_parameters].present?
            options[:additional_parameters].each do |k, v|
              additional_parameter << XmlNode.new('xsd:shipmentParameter') do |shipment_parameter|
                shipment_parameter << XmlNode.new('xsd:name', v['name'])
                shipment_parameter << XmlNode.new('xsd:value', v['value'])
              end
            end
          end
        end
        service_options << XmlNode.new('xsd1:carbonNeutralIndicator', options['carbon_indicator'])
        service_options << XmlNode.new('xsd1:codIndicator', options['cod_indicator'])
        service_options << XmlNode.new('xsd1:confirmDeliveryIndicator', options['confirm_delivery_indicator'])
        service_options << XmlNode.new('xsd1:deliveryOnSatIndicator', options['delivery_sat_indicator'])
        service_options << XmlNode.new('xsd1:handlingChargeIndicator', options['handling_charge_indicator'])
        service_options << XmlNode.new('xsd1:returnLabelIndicator', options['return_label_indicator'])
        service_options << XmlNode.new('xsd1:schedulePickupIndicator', options['scheduled_delivery_indicator'])
        if options['shipment_type'].present?
        service_options << XmlNode.new('xsd1:shipmentType', SHIPMENT_TYPE(options['shipment_type']))
          end
      end

      def build_location_node(location, xml)

        xml << XmlNode.new('xsd:postalCode', location.postal_code)
        xml << XmlNode.new('xsd:city', location.city)
        xml << XmlNode.new('xsd:state', location.state)
        xml << XmlNode.new('xsd:countryCode', location.country_code)
        xml << XmlNode.new('xsd:residentailIndicator', location.residential_indicator)
      end
















      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_s
      end




      def add_insured_node(*args)
        params, package_node = args.extract_options!, args[0]
        currency, value = params[:currency], params[:value].to_i
        package_node << XmlNode.new("PackageServiceOptions") do |package_service_options|
          package_service_options << XmlNode.new("DeclaredValue") do |declared_value|
            declared_value << XmlNode.new("CurrencyCode", currency)
            declared_value << XmlNode.new("MonetaryValue", (value.to_i))
          end
          package_service_options << XmlNode.new("InsuredValue") do |declared_value|
            declared_value << XmlNode.new("CurrencyCode", currency)
            declared_value << XmlNode.new("MonetaryValue", (value.to_i))
          end
        end
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        rates = []

        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          rate_estimates = []

          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            days_to_delivery = rated_shipment.get_text('GuaranteedDaysToDelivery').to_s.to_i
            days_to_delivery = nil if days_to_delivery == 0
            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                               service_name_for(origin, service_code),
                                               :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                               :insurance_price => rated_shipment.get_text('ServiceOptionsCharges/MonetaryValue').to_s.to_f,
                                               :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                               :service_code => service_code,
                                               :packages => packages,
                                               :delivery_range => [timestamp_from_business_day(days_to_delivery)],
                                               :negotiated_rate => rated_shipment.get_text('NegotiatedRates/NetSummaryCharges/GrandTotal/MonetaryValue').to_s.to_f)
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          tracking_number, origin, destination, status_code, status_description, delivery_signature = nil
          delivered, exception = false
          exception_event = nil
          shipment_events = []
          status = {}
          scheduled_delivery_date = nil

          first_shipment = xml.elements['/*/Shipment']
          first_package = first_shipment.elements['Package']
          tracking_number = first_shipment.get_text('ShipmentIdentificationNumber | Package/TrackingNumber').to_s

          # Build status hash
          status_node = first_package.elements['Activity/Status/StatusType']
          status_code = status_node.get_text('Code').to_s
          status_description = status_node.get_text('Description').to_s
          status = TRACKING_STATUS_CODES[status_code]

          if status_description =~ /out.*delivery/i
            status = :out_for_delivery
          end

          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_from_address_node(first_shipment.elements["#{location}/Address"])
          end

          # Get scheduled delivery date
          unless status == :delivered
            scheduled_delivery_date = parse_ups_datetime({
                                                             :date => first_shipment.get_text('ScheduledDeliveryDate'),
                                                             :time => nil
                                                         })
          end

          activities = first_package.get_elements('Activity')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Status/StatusType/Description').to_s
              zoneless_time = if (time = activity.get_text('Time')) &&
                  (date = activity.get_text('Date'))
                                time, date = time.to_s, date.to_s
                                hour, minute, second = time.scan(/\d{2}/)
                                year, month, day = date[0..3], date[4..5], date[6..7]
                                Time.utc(year, month, day, hour, minute, second)
                              end
              location = location_from_address_node(activity.elements['ActivityLocation/Address'])
              ShipmentEvent.new(description, zoneless_time, location)
            end

            shipment_events = shipment_events.sort_by(&:time)

            # UPS will sometimes archive a shipment, stripping all shipment activity except for the delivery
            # event (see test/fixtures/xml/delivered_shipment_without_events_tracking_response.xml for an example).
            # This adds an origin event to the shipment activity in such cases.
            if origin && !(shipment_events.count == 1 && status == :delivered)
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end

            # Has the shipment been delivered?
            if status == :delivered
              delivery_signature = activities.first.get_text('ActivityLocation/SignedForByName').to_s
              if !destination
                destination = shipment_events[-1].location
              end
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end

        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
                             :carrier => @@name,
                             :xml => response,
                             :request => last_request,
                             :status => status,
                             :status_code => status_code,
                             :status_description => status_description,
                             :delivery_signature => delivery_signature,
                             :scheduled_delivery_date => scheduled_delivery_date,
                             :shipment_events => shipment_events,
                             :delivered => delivered,
                             :exception => exception,
                             :exception_event => exception_event,
                             :origin => origin,
                             :destination => destination,
                             :tracking_number => tracking_number)
      end

      def location_from_address_node(address)
        return nil unless address
        Location.new(
            :country => node_text_or_nil(address.elements['CountryCode']),
            :postal_code => node_text_or_nil(address.elements['PostalCode']),
            :province => node_text_or_nil(address.elements['StateProvinceCode']),
            :city => node_text_or_nil(address.elements['City']),
            :address1 => node_text_or_nil(address.elements['AddressLine1']),
            :address2 => node_text_or_nil(address.elements['AddressLine2']),
            :address3 => node_text_or_nil(address.elements['AddressLine3'])
        )
      end

      def parse_ups_datetime(options = {})
        time, date = options[:time].to_s, options[:date].to_s
        if time.nil?
          hour, minute, second = 0
        else
          hour, minute, second = time.scan(/\d{2}/)
        end
        year, month, day = date[0..3], date[4..5], date[6..7]

        Time.utc(year, month, day, hour, minute, second)
      end

      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end

      def response_message(xml)
        xml.get_text('/*/Response/Error/ErrorDescription | /*/Response/ResponseStatusDescription').to_s
      end

      def commit(action, request, test = false)
        ssl_post(LIVE_URL, request.to_s, {"SOAPAction" => "urn:getUPSServiceDetails", "Content-Type" => "text/xml"})
      end


      def service_name_for(origin, code)
        origin = origin.country_code(:alpha2)

        name = case origin
                 when "CA" then
                   CANADA_ORIGIN_SERVICES[code]
                 when "MX" then
                   MEXICO_ORIGIN_SERVICES[code]
                 when *EU_COUNTRY_CODES then
                   EU_ORIGIN_SERVICES[code]
               end

        name ||= OTHER_NON_US_ORIGIN_SERVICES[code] unless name == 'US'
        name ||= DEFAULT_SERVICES[code]
      end

    end
  end
end
