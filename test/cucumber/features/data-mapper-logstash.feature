Feature: Data Mapper Logstash?
    Does the logstash package work as expected

    Scenario: Init Data Mapper Logstash
        Given I use parameters "init data-mapper-logstash --dev --env-file=.env.test"
        When I launch the platform with params
        Then The service "analytics-datastore-elastic-search" should be started
        And The service "data-mapper-logstash" should be started
        And There should be 2 services
        And The service "analytics-datastore-elastic-search" should have healthy containers
        And The service "data-mapper-logstash" should have healthy containers
        And The volume "es-data" should be created
        And The volume "logstash-data" should be created
        And There should be 2 volumes

    Scenario: Destroy Data Mapper Logstash
        Given I use parameters "destroy data-mapper-logstash --dev --env-file=.env.test"
        When I launch the platform with params
        Then The service "analytics-datastore-elastic-search" should be removed
        And The service "data-mapper-logstash" should be removed
        And There should be 0 services
        And The volume "es-data" should be removed
        And The volume "logstash-data" should be removed
        And There should be 0 volumes
