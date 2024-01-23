require 'net/http'
require 'nokogiri'
require 'telegram/bot'
require 'date'

def get_exchange_rates(date)
  url = URI.parse("https://bnm.md/en/official_exchange_rates?get_xml=1&date=#{date}")
  response = Net::HTTP.get_response(url)
  data = response.body

  doc = Nokogiri::XML(data)

  # Извлечение информации о курсах валют
  # Пример: извлечение курсов евро, доллара, гривны, лея и рубля
  euro_rate = doc.at_xpath('//Valute[@ID="47"]/Value')&.content
  usd_rate = doc.at_xpath('//Valute[@ID="44"]/Value')&.content
  uah_rate = doc.at_xpath('//Valute[@ID="53"]/Value')&.content  # Исправлен ID для гривны
  ron_rate = doc.at_xpath('//Valute[@ID="49"]/Value')&.content
  rub_rate = doc.at_xpath('//Valute[@ID="51"]/Value')&.content  # Исправлен ID для рубля

  # Возвращаем хэш с данными о курсах валют
  {
    'euro' => euro_rate,
    'usd' => usd_rate,
    'uah' => uah_rate,
    'ron' => ron_rate,
    'rub' => rub_rate
  }
end

# Инициализация телеграм-бота
token = '6716806477:AAEsJdC1I7wO1SRJm2AgHAeahlUqvR0nasg'
Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: 'Salut! Pentru afisarea cursului apasa Menu!')
    when '/get_rates'
      current_date = Date.today
      # Если сегодня суббота или воскресенье, то находим последний рабочий день (пятницу)
      if current_date.saturday?
        current_date -= 1
      elsif current_date.sunday?
        current_date -= 2
      end

      formatted_date = current_date.strftime('%d.%m.%Y')
      rates = get_exchange_rates(formatted_date)

      # Формируем текст для отправки в боте
      rates_text = "Curs valutar BNM, #{formatted_date}:\n"
      rates_text += "EUR: #{rates['euro']} MDL\n"
      rates_text += "USD: #{rates['usd']} MDL\n"
      rates_text += "UAH: #{rates['uah']} MDL\n"
      rates_text += "RON: #{rates['ron']} MDL\n"
      rates_text += "RUB: #{rates['rub']} MDL\n"
      rates_text += "Să aveți o zi productivă în continuare!"
      # Отправка информации о курсах валют
      bot.api.send_message(chat_id: message.chat.id, text: rates_text)
    end
  end
end
