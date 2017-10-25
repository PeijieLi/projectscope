Feature: publish tasks to all the teams and edit for each team

  As a student
  I want to see the tasks assigned to us for each iteration
  
  Background: I am on the instructor-dashboard page
    Given Create team "team1"
    Given I am logged in
    And I have "iteration_1" iterations created
    And I am on the "iteration dashboard" page
    And I follow "iteration_1"
    Given I create Task "customer meeting" to "meet with customer"
    When I follow "Add new task"
    And I fill in "task_title" with "create low-fi"
    And I fill in "task_description" with "mock up after the meeting"
    And I should see "customer meeting"
    And I check "tasks[customer meeting]"
    And I press "Create Task"
    Given I am logged in as "team1"
 

 
  
    Scenario: should be able to select iteration
      And I go to iteration dashboard
      And I should see "iteration_1"
      And I select "iteration_1"
     Scenario: should be able to view tasks iteration
      And I go to iteration dashboard
      And I should see "iteration_1"
      And I select "iteration_1"
      Then I should see graph for "iteration_1"
      
  