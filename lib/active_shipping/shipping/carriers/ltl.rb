# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class Ltl < Carrier
      self.retry_safe = true

      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"

      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://onlinetools.ups.com'


      LIMITED_ACCESS_TYPE = {
          "School" => "01",
          "Church" => "02",
          "Military Base/Installation" => "03",
          "Prison/Jail/Correctional Facility" => "04"
      }

      INSURANCE_CATEGORY = {
          "1" => "New General Merchandise",
          "2" => "Used General Merchandise",
          "3" => "Fragile goods",
          "4" => "Non-Perishable Foods/Beverages/Commodities",
          "5" => "Perishable/Temperature Controlled/Foods/Beverages/Commodities (Full Conditions)",
          "6" => "Laptops/Cellphones/PDAs/iPads/Tablets/Notebooks and Gaming systems",
          "7" => "Wine",
          "8" => "Radioactive/Hazardous/Restricted or Controlled Items"

      }

      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]

      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]

      HANDLING_UNIT_TYPE = ["Pallet", "Skid", "Bag", "Bale", "Box", "Bundle", "Carton", "Crate", "Cylinder", "Drum", "Gaylord", "Loose", "Pails", "Roll", "Other"]
      LINE_ITEM_CLASS = ["50", "55", "60", "65", "70", "77.5", "85", "92.5", "100", "125", "150", "200", "300", "400", "500"]

      def requirements
        [:loginId, :password, :licenseKey, :accountNumber]
      end

      # require 'active_shipping'
      # destination = ActiveMerchant::Shipping::Location.new(country: 'US', state: 'ON', city: 'Ottawa', zip: '90210' )
      # origin = ActiveMerchant::Shipping::Location.new(country: 'US', state: 'CA', city: 'Beverly Hills', zip: '90210' )
      # w = {'line1' => {'class_type' => 'class_t1', 'weight' => '4', 'description' => 'desc', 'NMFC_number' => '3', 'piece_type' => 'types', 'number_pieces'=>'4'}, 'line2' =>  {'class_type' => 'class_t1', 'weight' => '4', 'description' => 'desc', 'NMFC_number' => '3', 'piece_type' => 'types', 'number_pieces'=>'4'}}
      # package1 = ActiveMerchant::Shipping::Package.new(100, [93,10], cylinder: true)
      # package1.options['lines'] = w
      # packages = []
      # packages << package1
      # w = ActiveMerchant::Shipping::Ltl.new(loginId: '2324435', password: 'dufekl', licenseKey: 'eojewgjwewg', accountNumber: '345')
      # w.find_rates(origin, destination, packages, {dupa: 'dupa'})
      def find_rates(origin, destination, packages, options={})
        xml_request = XmlNode.new('freightShipmentQuoteRequest')
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        build_access_request(xml_request)
        build_rate_request(origin, destination, packages, options, xml_request)
        build_insurance_request(options, xml_request)
        build_commodity_request(origin, packages, xml_request)
        response = commit(:rates, save_request(xml_request.to_s), (options[:test] || false))
        puts xml_request
        parse_rate_response(origin, destination, packages, response, options)
      end

      protected

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
        xml_request << XmlNode.new('loginId', @options[:loginId])
        xml_request << XmlNode.new('Password', @options[:password])
        xml_request << XmlNode.new('licenceKey', @options[:licenseKey])
        xml_request << XmlNode.new('accountNumber', @options[:accountNumber])
        xml_request.to_s
      end

      def build_rate_request(origin, destination, packages, options={}, xml_request)
        xml_request << XmlNode.new('senderCity', origin.city)
        xml_request << XmlNode.new('senderState', origin.state)
        xml_request << XmlNode.new('senderZip', origin.zip)
        xml_request << XmlNode.new('senderCountryCode', origin.country)
        xml_request << XmlNode.new('receiverCity', destination.city)
        xml_request << XmlNode.new('receiverState', destination.state)
        xml_request << XmlNode.new('receiverZip', destination.zip)
        xml_request << XmlNode.new('receiverCountryCode', destination.country)
        #optionals
        xml_request << XmlNode.new('insidePickup', options[:inside_pickup])
        xml_request << XmlNode.new('insideDelivery', options[:inside_delivery])
        xml_request << XmlNode.new('liftgatePickup', options[:lift_gate_pickup])
        xml_request << XmlNode.new('liftgateDelivery', options[:lift_gate_delivery])
        xml_request << XmlNode.new('residentialPickup', options[:residential_pickup])
        xml_request << XmlNode.new('residentialDelivery', options[:residential_delivery])
        xml_request << XmlNode.new('tradeshowPickup', options[:trade_show_pickup])
        xml_request << XmlNode.new('tradeshowDelivery', options[:trade_show_delivery])
        xml_request << XmlNode.new('constructionSitePickup', options[:construction_site_pickup])
        xml_request << XmlNode.new('constructionSiteDelivery', options[:construction_site_delivery])
        xml_request << XmlNode.new('notifyBeforeDelivery', options[:notify_before_delivery])
        xml_request << XmlNode.new('limitedAccessPickup', options[:limited_access_pickup])
        # if limitedAccessPickup is true then limitedAccessPickupType required
        xml_request << XmlNode.new('limitedAccessPickupType', LIMITED_ACCESS_TYPE[options[:pickup_type]])
        xml_request << XmlNode.new('limitedAccessDelivery', options[:limited_access_delivery])
        # if limitedAccessDelivery is true then limitedAccessDeliveryType required
        xml_request << XmlNode.new('limitedAccessDeliveryType', LIMITED_ACCESS_TYPE[options[:delivery_type]])
        xml_request << XmlNode.new('collectOnDelivery', options[:COD_service])
        xml_request << XmlNode.new('collectOnDeliveryAmount', options[:CPD_service_amount])
        xml_request << XmlNode.new('CODIncludingFreightCharge', options[:included_freight_charges])
        xml_request << XmlNode.new('shipmentDate', options[:date_of_shipment_pickup])
        xml_request.to_s
      end

      # if InsuranceDetail is used then commdityDetails must be used
      def build_insurance_request(options={}, xml_request)
        xml_request << XmlNode.new('InsuranceDetail') do |insurance|
          insurance << XmlNode.new('insuranceCategory', INSURANCE_CATEGORY[options[:insurance_category_type]])
          insurance << XmlNode.new('insureCommodityValue', options[:insurance_commodity_value])
          insurance << XmlNode.new('insuranceIncludingFreightCharge', options[:included_the_freight_charges])
        end
        xml_request.to_s
      end

      def build_commodity_request(origin, packages, xml_request)
        imperial = ['US', 'LR', 'MM'].include?(origin.country)
        xml_request << XmlNode.new('commdityDetails') do |commodity|
          # do przemyślenia (czy sami oblicamy czy jest podane)
          commodity << XmlNode.new('is11FeetShipment', false)
          commodity << XmlNode.new('handlingUnitDetails') do |details|
            packages.each do |package|

              details << XmlNode.new('wsHandlingUnit') do |package_handling|
                package_handling << XmlNode.new('typeOfHandlingUnit', package.options[:units])
                package_handling << XmlNode.new('numberOfHandlingUnit', package.options[:number]) unless package.options[:number]
                package_handling << XmlNode.new('numberOfHandlingUnit', "1")
                if imperial
                  package_handling << XmlNode.new('handlingUnitHeight', package.inches[2])
                  package_handling << XmlNode.new('handlingUnitLength', package.inches[0])
                  package_handling << XmlNode.new('handlingUnitWidth', package.inches[1])
                else
                  package_handling << XmlNode.new('handlingUnitHeight', package.cm[2])
                  package_handling << XmlNode.new('handlingUnitLength', package.cm[0])
                  package_handling << XmlNode.new('handlingUnitWidth', package.cm[1])
                end
                package_handling << XmlNode.new('lineItemDetails') do |line_item_details|
                  package.options['lines'].each do |k, line|
                    line_item_details << XmlNode.new('wsLineItem') do |ws_line_item|
                      ws_line_item << XmlNode.new('lineItemClass', line['class_type'])
                      ws_line_item << XmlNode.new('lineItemWeight', line['weight'])
                      ws_line_item << XmlNode.new('lineIemDescription', line['description'])
                      ws_line_item << XmlNode.new('lineItemNMFC', line['NMFC_number'])
                      ws_line_item << XmlNode.new('lineItemPieceType', line['piece_type'])
                      ws_line_item << XmlNode.new('piecesOfLineItem', line['number_pieces'])
                      ws_line_item << XmlNode.new('isHazmatLineItem', line['hazmat'])
                      if line[:hazmat]
                        ws_line_item << XmlNode.new('lineItemHazmatInfo') do |line_item_hazmat|
                          line_item_hazmat << XmlNode.new('lineItemHazmatUNNumberHeader', line['UN_number'])
                          line_item_hazmat << XmlNode.new('lineItemHazmatUNNumber', line['UN_number_valid'])
                          line_item_hazmat << XmlNode.new('lineItemHazmatClass', line['hazmat_class'])
                          line_item_hazmat << XmlNode.new('lineItemHazmatEmContactPhone', line['hazmat_phone'])
                          line_item_hazmat << XmlNode.new('lineItemHazmatPackagingGroup', line['hazmat_group'])
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        xml_request.to_s
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        rates = []
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        puts "========"
        puts message
        puts "========"
        xml.elements.each('/*/Response') do |respond|
          puts "========"
          puts respond.get_text('ResponseStatusCode').to_s
          puts "========"
        end
        if success
          rate_estimates = []

          xml.elements.each('/*/freightShipmentQuoteResult') do |rated_shipment|
            service_code = rated_shipment.get_text('shipmentQuoteId').to_s
            days_to_delivery = rated_shipment.get_text('transitDays')
            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                               :name => rated_shipment.get_text('carrierName').to_s,
                                               :total_price => rated_shipment.get_text('totalPrice').to_s.to_f,
                                               :shipment_quote_id => service_code,
                                               :carrier_scac => rated_shipment.get_text('carrierSCAC').to_s,
                                               :delivery_range => [timestamp_from_business_day(days_to_delivery)],
                                               :guaranteed_service => rated_shipment.get_text('guaranteedService'),
                                               :high_cost_delivery_shipment => rated_shipment.get_text('highCostDeliveryShipment'),
                                               :interline => rated_shipment.get_text('interline'),
                                               :nmfcRequired => rated_shipment.get_text('nmfcRequired')
            )
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end

      def response_message(xml)
        xml.get_text('/*/Response/Error/ErrorDescription | /*/Response/ResponseStatusDescription').to_s
      end

      def commit(action, request, test = false)
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end
    end
  end
end
