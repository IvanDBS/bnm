# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'telegram/bot'
require 'date'

def get_exchange_rates(date)
  data = fetch_exchange_data(date)
  parse_exchange_rates(data)
end

def fetch_exchange_data(date)
  url = URI.parse("https://bnm.md/en/official_exchange_rates?get_xml=1&date=#{date}")
  response = Net::HTTP.get_response(url)
  response.body
end

def parse_exchange_rates(data)
  doc = Nokogiri::XML(data)

  {
    'euro' => extract_rate(doc, '47'),
    'usd' => extract_rate(doc, '44'),
    'uah' => extract_rate(doc, '53'), # Updated ID for UAH
    'ron' => extract_rate(doc, '49'),
    'rub' => extract_rate(doc, '51') # Updated ID for RUB
  }
end

def extract_rate(doc, valute_id)
  doc.at_xpath("//Valute[@ID='#{valute_id}']/Value")&.content
end

# Initializing the Telegram bot
token = 'YOUR_TELEGRAM_BOT_TOKEN'
Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: 'Salut! Pentru afisarea cursului apasa Menu!')
    when '/get_rates'
      current_date = Date.today
      # If today is Saturday or Sunday, find the last working day (Friday)
      if current_date.saturday?
        current_date -= 1
      elsif current_date.sunday?
        current_date -= 2
      end

      formatted_date = current_date.strftime('%d.%m.%Y')
      rates = get_exchange_rates(formatted_date)

      # Generating text to send in the bot
      rates_text = "Curs valutar BNM, #{formatted_date}:\n"
      rates_text += "EUR: #{rates['euro']} MDL\n"
      rates_text += "USD: #{rates['usd']} MDL\n"
      rates_text += "UAH: #{rates['uah']} MDL\n"
      rates_text += "RON: #{rates['ron']} MDL\n"
      rates_text += "RUB: #{rates['rub']} MDL\n"
      rates_text += 'Să aveți o zi productivă în continuare!'
      # Sending information about exchange rates
      bot.api.send_message(chat_id: message.chat.id, text: rates_text)
    end
  end
end
