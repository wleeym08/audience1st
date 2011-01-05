Feature: edit labels

  As a staff user
  So that I can choose what to track about our patrons
  I want to customize the labels that can be applied to customers

Background:

  Given I am logged in as staff

Scenario: no labels exist

  When I go to the edit contact info page for customer "Tom Foolery"
  Then I should see "Labels" within "fieldset#admin_form"
  And I should not see /\S+/ within "div#current_labels"