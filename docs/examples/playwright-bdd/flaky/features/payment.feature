Feature: Payment Processing
  As a logged-in user
  I want to pay for my order
  So that my purchase is completed

  Scenario: Process payment with credit card
    Given I am on the payment page with a pending order
    When I enter valid credit card details
    And I submit the payment form
    Then the payment should be processed successfully
    And I should see the payment confirmation with an order number
