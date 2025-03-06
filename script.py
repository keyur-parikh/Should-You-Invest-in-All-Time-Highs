# This here is to get S&P 500 data from yahoo finance, since 1988 and save it to a csv file
import yfinance as yf
import pandas as pd

ticker_symbol = "^GSPC"

start_date = "1988-01-01"

data = yf.download(ticker_symbol, start=start_date, interval="1d")

data.reset_index(inplace=True)

# I only want to keep the columns date and Close
data = data[["Date", "Close"]]

print(data.head())

# Now write it to a csv file
data.to_csv("sp500_data.csv", index=False)
print("Data saved to sp500_data.csv")