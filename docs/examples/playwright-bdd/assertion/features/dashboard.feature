Feature: Analytics Dashboard
  As an admin user
  I want to view the analytics dashboard
  So that I can monitor application metrics

  Scenario: View daily active users metric
    Given I am logged in as an admin user
    And I navigate to the analytics dashboard
    When I select the date range "Last 7 days"
    Then the daily active users count should be greater than 100
    And the chart should display 7 data points
