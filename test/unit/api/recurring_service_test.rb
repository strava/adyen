# encoding: UTF-8
require 'unit/api/test_helper'
require 'date'

describe Adyen::API::RecurringService do
  include APISpecHelper

  before do
    @params = {
      :reference => 'order-id',
      :amount => {
        :currency => 'EUR',
        :value => '1234',
      },
      :shopper => {
        :email => 's.hopper@example.com',
        :reference => 'user-id',
        :ip => '61.294.12.12',
        :statement => 'invoice number 123456'
      },
      :card => {
        :expiry_month => 12,
        :expiry_year => 2012,
        :holder_name => 'Simon わくわく Hopper',
        :number => '4444333322221111',
        :cvc => '737',
        # Maestro UK/Solo only
        #:issue_number => ,
        #:start_month => ,
        #:start_year => ,
      },
      # German's Direct Debit (Elektronisches Lastschriftverfahren)
      :elv => {
        :holder_name      => 'Simon わくわく Hopper',
        :number           => '1234567890',
        :bank_location    => 'Berlin',
        :bank_location_id => '12345678',
        :bank_name        => 'TestBank',
      }
    }
    @recurring = @object = Adyen::API::RecurringService.new(@params)
  end

  describe_request_body_of :list, '//recurring:listRecurringDetails/recurring:request' do
    it_should_validate_request_parameters :merchant_account,
                                          :shopper => [:reference]

    it "includes the merchant account handle" do
      text('./recurring:merchantAccount').must_equal 'SuperShopper'
    end

    it "includes the shopper's reference" do
      text('./recurring:shopperReference').must_equal 'user-id'
    end

    it "includes the type of contract, which is always `RECURRING'" do
      text('./recurring:recurring/payment:contract').must_equal 'RECURRING'
    end
  end

  describe_response_from :list, LIST_RESPONSE, 'listRecurringDetails' do
    it_should_return_params_for_each_xml_backend({
      :creation_date => DateTime.parse('2009-10-27T11:26:22.203+01:00'),
      :last_known_shopper_email => 's.hopper@example.com',
      :shopper_reference => 'user-id',
      :details => [
        {
          :card => {
            :expiry_date => Date.new(2012, 12, 31),
            :holder_name => 'S. Hopper',
            :number => '1111'
          },
          :recurring_detail_reference => 'RecurringDetailReference1',
          :variant => 'mc',
          :creation_date => DateTime.parse('2009-10-27T11:50:12.178+01:00')
        },
        {
          :bank => {
            :number => '123456789',
            :bank_location_id => 'bank-location-id',
            :bank_name => 'AnyBank',
            :bic => 'BBBBCCLLbbb',
            :country_code => 'NL',
            :iban => 'NL69PSTB0001234567',
            :holder_name => 'S. Hopper'
          },
          :recurring_detail_reference => 'RecurringDetailReference2',
          :variant => 'IDEAL',
          :creation_date => DateTime.parse('2009-10-27T11:26:22.216+01:00')
        },
        {
          :elv => {
            :holder_name      => 'S. Hopper',
            :number           => '1234567890',
            :bank_location    => 'Berlin',
            :bank_location_id => '12345678',
            :bank_name        => 'TestBank',
          },
          :recurring_detail_reference => 'RecurringDetailReference3',
          :variant => 'elv',
          :creation_date => DateTime.parse('2009-10-27T11:26:22.216+01:00')
        }
      ],
    })

    it "returns an array with just the detail references" do
      @response.references.must_equal %w{ RecurringDetailReference1 RecurringDetailReference2 RecurringDetailReference3 }
    end
  end

  describe_response_from :list, LIST_EMPTY_RESPONSE, 'listRecurringDetails' do
    it "returns an empty hash when there are no details" do
      @recurring.list.params.must_equal({})
    end

    it "returns an empty array when there are no references" do
      @response.references.must_equal []
    end
  end

  describe_request_body_of :disable, '//recurring:disable/recurring:request' do
    it_should_validate_request_parameters :merchant_account,
                                          :shopper => [:reference]

    it "includes the merchant account handle" do
      text('./recurring:merchantAccount').must_equal 'SuperShopper'
    end

    it "includes the shopper's reference" do
      text('./recurring:shopperReference').must_equal 'user-id'
    end

    it "does not provide a recurring details reference by default" do
      xpath('./recurring:recurringDetailReference').must_be :empty?
    end

    it "includes the shopper's recurring detail reference if it is given" do
      @recurring.params[:recurring_detail_reference] = 'RecurringDetailReference1'
      text('./recurring:recurringDetailReference').must_equal 'RecurringDetailReference1'
    end
  end

  describe_response_from :disable, (DISABLE_RESPONSE % '[detail-successfully-disabled]'), 'disable' do
    it "returns whether or not it was disabled" do
      @response.must_be :success?
      @response.must_be :disabled?

      stub_net_http(DISABLE_RESPONSE % '[all-details-successfully-disabled]')
      @response = @recurring.disable
      @response.must_be :success?
      @response.must_be :disabled?
    end

    it_should_return_params_for_each_xml_backend(:response => '[detail-successfully-disabled]')
  end

  describe_request_body_of :store_token, '//recurring:storeToken/recurring:request' do
    it_should_validate_request_parameters :merchant_account,
                                          :shopper => [:email, :reference]

    it "includes the merchant account handle" do
      text('./recurring:merchantAccount').must_equal 'SuperShopper'
    end

    it "includes the shopper's reference" do
      text('./recurring:shopperReference').must_equal 'user-id'
    end

    it "includes the shopper's email" do
      text('./recurring:shopperEmail').must_equal 's.hopper@example.com'
    end

    it "includes the creditcard details" do
      xpath('./recurring:card') do |card|
        # there's no reason why Nokogiri should escape these characters, but as long as they're correct
        card.text('./payment:holderName').must_equal 'Simon わくわく Hopper'
        card.text('./payment:number').must_equal '4444333322221111'
        card.text('./payment:cvc').must_equal '737'
        card.text('./payment:expiryMonth').must_equal '12'
        card.text('./payment:expiryYear').must_equal '2012'
      end
    end

    it "formats the creditcard's expiry month as a two digit number" do
      @recurring.params[:card][:expiry_month] = 6
      text('./recurring:card/payment:expiryMonth').must_equal '06'
    end

    it "includes the necessary recurring and one-click contract info if the `:recurring' param is truthful" do
      text('./recurring:recurring/payment:contract').must_equal 'RECURRING'
    end
  end
  
  describe_request_body_of :store_token, '//recurring:storeToken/recurring:request' do
    it_should_validate_request_parameters :merchant_account,
                                          :shopper => [:email, :reference]

    it "includes the merchant account handle" do
      text('./recurring:merchantAccount').must_equal 'SuperShopper'
    end

    it "includes the shopper's reference" do
      text('./recurring:shopperReference').must_equal 'user-id'
    end

    it "includes the shopper's email" do
      text('./recurring:shopperEmail').must_equal 's.hopper@example.com'
    end

    it "includes the ELV details" do
      xpath('./recurring:elv') do |elv|
        # there's no reason why Nokogiri should escape these characters, but as long as they're correct        
        elv.text('./payment:accountHolderName').must_equal 'Simon わくわく Hopper'
        elv.text('./payment:bankAccountNumber').must_equal '1234567890'
        elv.text('./payment:bankLocation').must_equal 'Berlin'
        elv.text('./payment:bankLocationId').must_equal '12345678'
        elv.text('./payment:bankName').must_equal 'TestBank'
      end
    end

    it "includes the necessary recurring and one-click contract info if the `:recurring' param is truthful" do
      text('./recurring:recurring/payment:contract').must_equal 'RECURRING'
    end
  end

  describe_response_from :disable, (DISABLE_RESPONSE % '[detail-successfully-disabled]'), 'disable' do
    it "returns whether or not it was disabled" do
      @response.must_be :success?
      @response.must_be :disabled?

      stub_net_http(DISABLE_RESPONSE % '[all-details-successfully-disabled]')
      @response = @recurring.disable
      @response.must_be :success?
      @response.must_be :disabled?
    end

    it_should_return_params_for_each_xml_backend(:response => '[detail-successfully-disabled]')
  end
end
