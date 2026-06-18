Feature: Product Search
  As a user
  I want to search for products
  So that I can find what I need quickly

  Scenario: Search for products by keyword
    Given I am on the product catalog page
    When I enter "wireless headphones" in the search box
    And I submit the search query
    Then I should see at least 5 product results
    And each product should display a name and price
