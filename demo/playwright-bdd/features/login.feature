Feature: User Login
  As a registered user
  I want to log in to the application
  So that I can access my account

  Scenario: Successful login with valid credentials
    Given I am on the login page
    When I enter username "test@example.com"
    And I enter password "SecurePass123"
    And I click the login button
    Then I should be redirected to the dashboard
    And I should see the welcome message "Welcome back, Test User"
