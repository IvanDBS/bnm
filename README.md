# BNM Exchange Rates Telegram Bot

This Telegram bot provides exchange rates from the National Bank of Moldova (BNM). It fetches the official exchange rates for the current date or the latest working day (in case today is Saturday or Sunday) and sends them to the user upon request.

## Features

- Displays exchange rates for EUR, USD, UAH, RON, and RUB.
- Automatically adjusts to the latest working day if today is a weekend.
- Provides a user-friendly interface to request exchange rates.

## Usage

1. Start the bot by sending the `/start` command.
2. To get the latest exchange rates, type `/get_rates`.
3. The bot will respond with the exchange rates for the current or latest working day.

## Technologies Used

- Ruby
- Nokogiri gem for parsing XML data
- Telegram API for interacting with Telegram users
