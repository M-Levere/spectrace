Feature: Shopping Cart Checkout
  As a logged-in user
  I want to complete my purchase
  So that my order is placed

  Scenario: Complete checkout with valid payment details
    Given I am logged in and have items in my shopping cart
    When I proceed to checkout
    And I enter my shipping address
    And I click the "Place Order" button
    Then I should see the order confirmation page
    And I should receive an order confirmation number
